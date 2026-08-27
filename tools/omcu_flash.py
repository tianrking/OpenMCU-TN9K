#!/usr/bin/env python3
"""通过 UART 向已固化的 OpenMCU Bootloader 烧录独立应用镜像。"""

from __future__ import annotations

import argparse
import dataclasses
import struct
import sys
import time
import zlib
from pathlib import Path
from typing import List, Optional

import omcu_image


SOF = b"\xA5\x5A"
PROTOCOL_VERSION = 1
FRAME_HEADER = struct.Struct("<BHH")
FRAME_CRC = struct.Struct("<I")
FRAME_MAX_PAYLOAD = 128
DATA_BYTES_PER_FRAME = FRAME_MAX_PAYLOAD - 4

CMD_HELLO = 0x01
CMD_BEGIN = 0x02
CMD_DATA = 0x03
CMD_END = 0x04
CMD_BOOT = 0x05

RESP_HELLO = 0x81
RESP_ACK = 0x82
RESP_NACK = 0x83
HELLO_CAP_BEGIN_IDEMPOTENT = 0x01


class ProtocolError(RuntimeError):
    """The serial peer did not satisfy the OpenMCU update protocol."""


@dataclasses.dataclass(frozen=True)
class Frame:
    frame_type: int
    sequence: int
    payload: bytes


def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def encode_frame(frame: Frame) -> bytes:
    if not 0 <= frame.frame_type <= 0xFF:
        raise ProtocolError("帧类型必须是 8 位整数")
    if not 0 <= frame.sequence <= 0xFFFF:
        raise ProtocolError("帧序号必须是 16 位整数")
    if len(frame.payload) > FRAME_MAX_PAYLOAD:
        raise ProtocolError("帧负载超过 Bootloader 协议上限")
    body = FRAME_HEADER.pack(frame.frame_type, frame.sequence, len(frame.payload)) + frame.payload
    return SOF + body + FRAME_CRC.pack(_crc32(body))


def decode_frame(packet: bytes) -> Frame:
    if len(packet) < len(SOF) + FRAME_HEADER.size + FRAME_CRC.size:
        raise ProtocolError("帧长度不足")
    if packet[:2] != SOF:
        raise ProtocolError("帧起始标记错误")
    frame_type, sequence, length = FRAME_HEADER.unpack_from(packet, len(SOF))
    if length > FRAME_MAX_PAYLOAD:
        raise ProtocolError("帧声明的负载长度超过上限")
    expected_length = len(SOF) + FRAME_HEADER.size + length + FRAME_CRC.size
    if len(packet) != expected_length:
        raise ProtocolError("帧长度与声明的负载长度不一致")
    body = packet[len(SOF):-FRAME_CRC.size]
    received_crc = FRAME_CRC.unpack_from(packet, len(packet) - FRAME_CRC.size)[0]
    if received_crc != _crc32(body):
        raise ProtocolError("帧 CRC32 校验失败")
    return Frame(frame_type, sequence, body[FRAME_HEADER.size:])


class SerialTransport:
    def __init__(self, port: str, baud: int) -> None:
        try:
            import serial  # type: ignore
        except ModuleNotFoundError as exc:
            raise ProtocolError(
                "缺少 pyserial；请执行 `python -m pip install pyserial` 后重试"
            ) from exc
        self._serial = serial.Serial(
            port=port,
            baudrate=baud,
            timeout=0.05,
            write_timeout=2.0,
        )
        self._serial.reset_input_buffer()
        self._serial.reset_output_buffer()

    def close(self) -> None:
        self._serial.close()

    def write(self, packet: bytes) -> None:
        written = self._serial.write(packet)
        if written != len(packet):
            raise ProtocolError(f"串口只写入了 {written}/{len(packet)} 字节")
        # Do not call pyserial.flush() here. POSIX implements it with
        # tcdrain(), which can wait forever on AppleUSBFTDI after a Tang board
        # power cycle. Stop-and-wait framing already supplies the required
        # ordering: write() has a finite write_timeout and exchange() does not
        # send another command until the matching response has arrived.
        deadline = time.monotonic() + 2.0
        while True:
            try:
                pending = self._serial.out_waiting
            except (AttributeError, OSError):
                break
            if pending == 0:
                break
            if time.monotonic() >= deadline:
                raise ProtocolError("串口发送队列在 2 秒内未排空")
            time.sleep(0.001)

    def read_exact(self, length: int, timeout: float) -> bytes:
        deadline = time.monotonic() + timeout
        received = bytearray()
        while len(received) < length:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("等待串口数据超时")
            self._serial.timeout = min(remaining, 0.05)
            chunk = self._serial.read(length - len(received))
            if chunk:
                received.extend(chunk)
        return bytes(received)

    def read_frame(self, timeout: float) -> Frame:
        deadline = time.monotonic() + timeout
        previous = b""
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("等待 Bootloader 帧超时")
            current = self.read_exact(1, remaining)
            if previous == SOF[:1] and current == SOF[1:]:
                break
            previous = current

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("读取帧头超时")
        header = self.read_exact(FRAME_HEADER.size, remaining)
        frame_type, sequence, length = FRAME_HEADER.unpack(header)
        if length > FRAME_MAX_PAYLOAD:
            raise ProtocolError("设备返回的帧负载超过协议上限")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("读取帧负载超时")
        payload = self.read_exact(length, remaining)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("读取帧 CRC 超时")
        crc = self.read_exact(FRAME_CRC.size, remaining)
        return decode_frame(SOF + header + payload + crc)


class Sequence:
    def __init__(self) -> None:
        self._value = 1

    def next(self) -> int:
        value = self._value
        self._value = (self._value + 1) & 0xFFFF
        if self._value == 0:
            self._value = 1
        return value


def exchange(
    transport: SerialTransport,
    frame: Frame,
    *,
    timeout: float,
    retries: int,
    expected_type: int = RESP_ACK,
) -> Frame:
    packet = encode_frame(frame)
    last_error: Optional[BaseException] = None
    for _attempt in range(retries):
        transport.write(packet)
        try:
            response = transport.read_frame(timeout)
        except (TimeoutError, ProtocolError) as exc:
            last_error = exc
            continue
        if response.sequence != frame.sequence:
            last_error = ProtocolError(
                f"收到序号 {response.sequence}，期望 {frame.sequence} 的响应"
            )
            continue
        if response.frame_type == RESP_NACK:
            code = response.payload[0] if response.payload else None
            raise ProtocolError(f"Bootloader 拒绝命令，错误码：{code}")
        if response.frame_type != expected_type:
            raise ProtocolError(
                f"Bootloader 响应类型为 0x{response.frame_type:02x}，"
                f"期望 0x{expected_type:02x}"
            )
        return response
    raise ProtocolError(f"命令重试 {retries} 次后未获得有效响应：{last_error}")


def wait_for_bootloader(
    transport: SerialTransport,
    sequence: Sequence,
    *,
    connect_timeout: float,
) -> Frame:
    deadline = time.monotonic() + connect_timeout
    last_error: Optional[BaseException] = None
    while time.monotonic() < deadline:
        frame = Frame(CMD_HELLO, sequence.next(), b"")
        try:
            return exchange(
                transport,
                frame,
                timeout=0.35,
                retries=1,
                expected_type=RESP_HELLO,
            )
        except ProtocolError as exc:
            last_error = exc
            time.sleep(0.05)
    raise ProtocolError(
        "未找到 Bootloader。请确认 FPGA 已固化 MCU 固件、串口连到 UART0，"
        "然后在连接期间按一次复位键。最后一次错误：{}".format(last_error)
    )


def hello_text(response: Frame) -> str:
    if len(response.payload) != 16:
        raise ProtocolError("HELLO 响应长度错误")
    protocol, valid, slot, _reserved = response.payload[:4]
    sequence, payload_bytes, hardware_abi = struct.unpack_from("<III", response.payload, 4)
    if protocol != PROTOCOL_VERSION:
        raise ProtocolError(
            f"设备协议版本为 {protocol}，工具要求 {PROTOCOL_VERSION}"
        )
    if valid:
        return (
            f"已连接：当前槽 A/B={slot}，应用序号={sequence}，"
            f"应用大小={payload_bytes} 字节，硬件 ABI=0x{hardware_abi:08x}"
        )
    return f"已连接：当前没有可启动应用，硬件 ABI=0x{hardware_abi:08x}"


def hello_capabilities(response: Frame) -> int:
    if len(response.payload) != 16:
        raise ProtocolError("HELLO 响应长度错误")
    return response.payload[3]


def begin_retry_count(capabilities: int, requested_retries: int) -> int:
    return (requested_retries
            if capabilities & HELLO_CAP_BEGIN_IDEMPOTENT
            else 1)


def program_image(args: argparse.Namespace) -> int:
    raw_image = Path(args.image).read_bytes()
    header, payload = omcu_image.parse_image(
        raw_image, expected_hardware_abi=args.hardware_abi
    )
    if header.state != omcu_image.STATE_STAGING:
        raise ProtocolError("只允许烧录 staging 状态的 .omcu 镜像")

    transport = SerialTransport(args.port, args.baud)
    sequence = Sequence()
    try:
        hello = wait_for_bootloader(
            transport, sequence, connect_timeout=args.connect_timeout
        )
        print(hello_text(hello))

        capabilities = hello_capabilities(hello)
        begin_retries = begin_retry_count(capabilities, args.retries)
        if (args.verify_begin_replay and not (
            capabilities & HELLO_CAP_BEGIN_IDEMPOTENT
        )):
            raise ProtocolError(
                "Bootloader 未声明 BEGIN 幂等能力，不能执行重放 HIL"
            )
        if begin_retries == 1 and args.retries > 1:
            print("Bootloader 未声明 BEGIN 幂等能力；擦除阶段不自动重发。")
        print("正在校验当前槽并擦除新镜像占用页…")

        begin_frame = Frame(CMD_BEGIN, sequence.next(), header.pack())
        exchange(
            transport,
            begin_frame,
            timeout=args.erase_timeout,
            retries=begin_retries,
        )
        print("已擦除非活动槽的新镜像占用页，开始写入应用镜像…")

        replay_begin = args.verify_begin_replay
        for offset in range(0, len(payload), DATA_BYTES_PER_FRAME):
            chunk = payload[offset:offset + DATA_BYTES_PER_FRAME]
            exchange(
                transport,
                Frame(CMD_DATA, sequence.next(), struct.pack("<I", offset) + chunk),
                timeout=args.data_timeout,
                retries=args.retries,
            )
            print(f"\r写入 {offset + len(chunk)}/{len(payload)} 字节", end="", flush=True)
            if replay_begin:
                # Use a fresh sequence for the explicit HIL replay. Reusing
                # the original sequence could accept a delayed first ACK and
                # would not prove that the loader handled this second BEGIN.
                replay_frame = Frame(
                    CMD_BEGIN, sequence.next(), header.pack()
                )
                exchange(
                    transport,
                    replay_frame,
                    timeout=args.erase_timeout,
                    retries=1,
                )
                replay_begin = False
                print("\nPASS: BEGIN 在 DATA 之后重放且保留写入进度。")
        print()

        exchange(
            transport,
            Frame(CMD_END, sequence.next(), b""),
            timeout=args.data_timeout,
            retries=args.retries,
        )
        print("Bootloader 已完成 User Flash 回读 CRC 校验并原子提交新槽。")

        if not args.no_boot:
            exchange(
                transport,
                Frame(CMD_BOOT, sequence.next(), b""),
                timeout=args.data_timeout,
                retries=args.retries,
            )
            print("已请求 Bootloader 切换到新应用。")
        return 0
    finally:
        transport.close()


def _parse_int(text: str) -> int:
    return int(text, 0)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Windows 例：COM5")
    parser.add_argument("--image", required=True, help="CMake 生成的 .omcu 文件")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--connect-timeout", type=float, default=8.0,
                        help="等待用户按复位并进入 Bootloader 的秒数")
    parser.add_argument("--erase-timeout", type=float, default=30.0,
                        help="BEGIN 校验当前槽并擦除占用页的单次等待秒数")
    parser.add_argument("--data-timeout", type=float, default=3.0,
                        help="DATA/END/BOOT 单次等待秒数")
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--hardware-abi", type=_parse_int,
                        default=omcu_image.DEFAULT_HARDWARE_ABI)
    parser.add_argument("--no-boot", action="store_true",
                        help="提交后保持在 Bootloader，方便诊断")
    parser.add_argument("--verify-begin-replay", action="store_true",
                        help="HIL：首个 DATA 后重放 BEGIN，验证进度不被擦除")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.baud <= 0 or args.retries <= 0:
        parser.error("--baud 和 --retries 必须为正数")
    try:
        return program_image(args)
    except (OSError, ProtocolError, omcu_image.ImageError) as exc:
        parser.error(str(exc))
    return 2


if __name__ == "__main__":
    sys.exit(main())
