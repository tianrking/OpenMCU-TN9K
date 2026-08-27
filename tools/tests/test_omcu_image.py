from __future__ import annotations

import dataclasses
import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import omcu_image  # noqa: E402


class OpenMcuImageTests(unittest.TestCase):
    def test_state_encoding_matches_flash608k_program_polarity(self) -> None:
        self.assertEqual(omcu_image.FORMAT_VERSION, 2)
        self.assertEqual(omcu_image.STATE_ERASED, 0x00000000)
        self.assertEqual(omcu_image.STATE_STAGING, 0x00000001)
        self.assertEqual(omcu_image.STATE_COMMITTED, 0x00000002)

    def test_build_pads_payload_and_validates_all_integrity_fields(self) -> None:
        image = omcu_image.build_image(b"\x01\x02\x03\x04\x05")
        header, payload = omcu_image.parse_image(
            image, expected_hardware_abi=omcu_image.DEFAULT_HARDWARE_ABI
        )

        self.assertEqual(header.payload_bytes, 8)
        self.assertEqual(payload, b"\x01\x02\x03\x04\x05\xff\xff\xff")
        self.assertEqual(header.state, omcu_image.STATE_STAGING)
        self.assertEqual(header.load_address, omcu_image.APPLICATION_LOAD_ADDRESS)
        self.assertEqual(header.entry_address, omcu_image.APPLICATION_LOAD_ADDRESS)

    def test_commit_transition_preserves_header_crc(self) -> None:
        header, payload = omcu_image.parse_image(omcu_image.build_image(b"test"))
        committed = dataclasses.replace(header, state=omcu_image.STATE_COMMITTED)
        self.assertEqual(omcu_image.header_crc32(committed), header.header_crc32)
        parsed, parsed_payload = omcu_image.parse_image(committed.pack() + payload)
        self.assertEqual(parsed.state, omcu_image.STATE_COMMITTED)
        self.assertEqual(parsed_payload, payload)

    def test_rejects_payload_corruption_and_unknown_state(self) -> None:
        image = bytearray(omcu_image.build_image(b"payload"))
        image[-1] ^= 0x01
        with self.assertRaisesRegex(omcu_image.ImageError, "payload CRC"):
            omcu_image.parse_image(bytes(image))

        header, payload = omcu_image.parse_image(omcu_image.build_image(b"payload"))
        bad_state = dataclasses.replace(header, state=0xFFFFFFF8)
        with self.assertRaisesRegex(omcu_image.ImageError, "state"):
            omcu_image.parse_image(bad_state.pack() + payload)

    def test_rejects_a_binary_larger_than_an_ab_slot(self) -> None:
        with self.assertRaisesRegex(omcu_image.ImageError, "slot limit"):
            omcu_image.build_image(b"\x00" * (omcu_image.PAYLOAD_MAX_BYTES + 1))


if __name__ == "__main__":
    unittest.main()
