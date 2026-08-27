from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import omcu_flash  # noqa: E402


class OpenMcuFlashProtocolTests(unittest.TestCase):
    def test_transport_write_does_not_use_unbounded_posix_drain(self) -> None:
        class FakeSerial:
            def __init__(self) -> None:
                self.packet = b""
                self.out_waiting = 0

            def write(self, packet: bytes) -> int:
                self.packet = packet
                return len(packet)

            def flush(self) -> None:
                raise AssertionError("tcdrain must not be called")

        fake = FakeSerial()
        transport = object.__new__(omcu_flash.SerialTransport)
        transport._serial = fake
        transport.write(b"hello")
        self.assertEqual(fake.packet, b"hello")

    def test_frame_round_trip(self) -> None:
        original = omcu_flash.Frame(omcu_flash.CMD_DATA, 0x1234, b"\x00\x01payload")
        self.assertEqual(omcu_flash.decode_frame(omcu_flash.encode_frame(original)), original)

    def test_crc_and_length_corruption_are_rejected(self) -> None:
        packet = bytearray(omcu_flash.encode_frame(omcu_flash.Frame(1, 2, b"abc")))
        packet[-1] ^= 0x01
        with self.assertRaisesRegex(omcu_flash.ProtocolError, "CRC32"):
            omcu_flash.decode_frame(bytes(packet))

        with self.assertRaisesRegex(omcu_flash.ProtocolError, "长度"):
            omcu_flash.decode_frame(bytes(packet[:-1]))

    def test_data_chunk_fits_the_bootloader_frame_limit(self) -> None:
        payload = b"\xff" * omcu_flash.DATA_BYTES_PER_FRAME
        frame = omcu_flash.Frame(omcu_flash.CMD_DATA, 1, b"\x00\x00\x00\x00" + payload)
        self.assertEqual(len(frame.payload), omcu_flash.FRAME_MAX_PAYLOAD)
        self.assertEqual(omcu_flash.decode_frame(omcu_flash.encode_frame(frame)), frame)

    def test_begin_retries_require_bootloader_idempotence_capability(self) -> None:
        legacy = bytes((omcu_flash.PROTOCOL_VERSION, 1, 0, 0)) + struct.pack(
            "<III", 3, 656, 9
        )
        capable = bytearray(legacy)
        capable[3] = omcu_flash.HELLO_CAP_BEGIN_IDEMPOTENT

        legacy_hello = omcu_flash.Frame(omcu_flash.RESP_HELLO, 1, legacy)
        capable_hello = omcu_flash.Frame(omcu_flash.RESP_HELLO, 1, bytes(capable))
        self.assertEqual(omcu_flash.hello_capabilities(legacy_hello), 0)
        self.assertEqual(
            omcu_flash.begin_retry_count(
                omcu_flash.hello_capabilities(legacy_hello), 3
            ),
            1,
        )
        self.assertEqual(
            omcu_flash.begin_retry_count(
                omcu_flash.hello_capabilities(capable_hello), 3
            ),
            3,
        )

        with self.assertRaisesRegex(omcu_flash.ProtocolError, "HELLO"):
            omcu_flash.hello_capabilities(
                omcu_flash.Frame(omcu_flash.RESP_HELLO, 1, b"short")
            )


if __name__ == "__main__":
    unittest.main()
