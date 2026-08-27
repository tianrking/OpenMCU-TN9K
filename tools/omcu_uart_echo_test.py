#!/usr/bin/env python3
"""Verify an OpenMCU UART echo application through a host serial adapter."""

from __future__ import annotations

import argparse
import hashlib
import sys
import time
from pathlib import Path
from typing import List, Optional


class UartEchoError(RuntimeError):
    """The serial echo path did not preserve the transmitted byte stream."""


def block_pattern(block_index: int, length: int) -> bytes:
    """Return a deterministic pattern whose phase changes for every block."""
    return bytes(
        ((index * 73 + block_index * 29 + 19) & 0xFF)
        for index in range(length)
    )


def read_exact(connection: object, length: int, timeout: float) -> bytes:
    deadline = time.monotonic() + timeout
    received = bytearray()
    while len(received) < length and time.monotonic() < deadline:
        chunk = connection.read(length - len(received))
        if chunk:
            received.extend(chunk)
    return bytes(received)


def first_mismatch(expected: bytes, received: bytes) -> int:
    for index, (wanted, actual) in enumerate(zip(expected, received)):
        if wanted != actual:
            return index
    return min(len(expected), len(received))


def run_test(
    port: str,
    *,
    baud: int,
    timeout: float,
    probe_repeats: int,
    block_bytes: int,
    blocks: int,
) -> List[str]:
    try:
        import serial  # type: ignore
    except ModuleNotFoundError as exc:
        raise UartEchoError(
            "missing pyserial; run `python -m pip install pyserial`"
        ) from exc

    lines: List[str] = []
    probe = b"OpenMCU UART echo test\r\n" + bytes(range(256)) * probe_repeats
    expected_hash = hashlib.sha256()
    received_hash = hashlib.sha256()
    started = time.monotonic()

    with serial.Serial(
        port=port,
        baudrate=baud,
        timeout=0.05,
        write_timeout=timeout,
    ) as connection:
        connection.reset_input_buffer()
        connection.reset_output_buffer()

        probe_received = bytearray()
        for index, value in enumerate(probe):
            if connection.write(bytes((value,))) != 1:
                raise UartEchoError(f"short probe write at byte {index}")
            echoed = read_exact(connection, 1, timeout)
            if echoed != bytes((value,)):
                raise UartEchoError(
                    "probe mismatch at byte {}: tx={:02x}, rx={}".format(
                        index, value, echoed.hex() if echoed else "timeout"
                    )
                )
            probe_received.extend(echoed)

        lines.append(f"PASS byte-domain {len(probe_received)}/{len(probe)} bytes")
        lines.append(
            "PROBE_SHA256 " + hashlib.sha256(probe_received).hexdigest()
        )

        for block in range(blocks):
            payload = block_pattern(block, block_bytes)
            expected_hash.update(payload)
            written = connection.write(payload)
            if written != len(payload):
                raise UartEchoError(
                    f"short block write {block}: {written}/{len(payload)}"
                )
            echoed = read_exact(connection, len(payload), timeout)
            if echoed != payload:
                raise UartEchoError(
                    "block {} mismatch: rx={}/{}, first_mismatch={}".format(
                        block,
                        len(echoed),
                        len(payload),
                        first_mismatch(payload, echoed),
                    )
                )
            received_hash.update(echoed)

    elapsed = time.monotonic() - started
    total = block_bytes * blocks
    lines.append(f"PASS sustained-blocks {blocks}/{blocks}")
    lines.append(f"PASS total {total}/{total} bytes elapsed={elapsed:.3f}s")
    lines.append("EXPECTED_SHA256 " + expected_hash.hexdigest())
    lines.append("RECEIVED_SHA256 " + received_hash.hexdigest())
    if expected_hash.digest() != received_hash.digest():
        raise UartEchoError("aggregate SHA-256 mismatch")
    lines.append(f"RESULT PASS UART_ECHO {port} {baud}_8N1")
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument(
        "--timeout", type=float, default=5.0,
        help="maximum seconds for each echoed byte or block",
    )
    parser.add_argument("--probe-repeats", type=int, default=4)
    parser.add_argument("--block-bytes", type=int, default=2048)
    parser.add_argument("--blocks", type=int, default=32)
    parser.add_argument("--log", type=Path, help="save the passing transcript")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if (
        args.baud <= 0
        or args.timeout <= 0.0
        or args.probe_repeats <= 0
        or args.block_bytes <= 0
        or args.blocks <= 0
    ):
        parser.error("baud, timeout, repeats, block size and block count must be positive")
    try:
        lines = run_test(
            args.port,
            baud=args.baud,
            timeout=args.timeout,
            probe_repeats=args.probe_repeats,
            block_bytes=args.block_bytes,
            blocks=args.blocks,
        )
    except (OSError, UartEchoError) as exc:
        parser.error(str(exc))
    for line in lines:
        print(line)
    if args.log is not None:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        args.log.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
