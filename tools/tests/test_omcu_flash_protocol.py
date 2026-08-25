from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import omcu_flash  # noqa: E402


class OpenMcuFlashProtocolTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
