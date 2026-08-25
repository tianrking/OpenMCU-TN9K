#!/usr/bin/env python3
"""Create and validate independent OpenMCU application images.

The generated .omcu file is deliberately separate from the FPGA .fs image:
the .fs contains the bootloader, while this file is transferred later to the
GW1NR-9C User Flash by tools/omcu_flash.py.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import struct
import sys
import zlib
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


MAGIC = 0x4F4D4355
FORMAT_VERSION = 1
HEADER_BYTES = 64
HEADER_STRUCT = struct.Struct("<IHHIIIIIIII6I")
STATE_OFFSET = 32
HEADER_CRC_OFFSET = 36

STATE_ERASED = 0xFFFFFFFF
STATE_STAGING = 0xFFFFFFFE
STATE_COMMITTED = 0xFFFFFFFC

USER_FLASH_BYTES = 77824
USER_FLASH_PAGE_BYTES = 2048
SLOT_PAGES = 18
SLOT_BYTES = SLOT_PAGES * USER_FLASH_PAGE_BYTES
PAYLOAD_MAX_BYTES = SLOT_BYTES - HEADER_BYTES

APPLICATION_LOAD_ADDRESS = 0x10000000
DEFAULT_HARDWARE_ABI = 0x00000008


class ImageError(ValueError):
    """An image is malformed or violates the fixed bootloader contract."""


@dataclasses.dataclass(frozen=True)
class ImageHeader:
    magic: int
    format_version: int
    header_bytes: int
    hardware_abi: int
    load_address: int
    entry_address: int
    payload_bytes: int
    payload_crc32: int
    sequence: int
    state: int
    header_crc32: int
    reserved: Tuple[int, int, int, int, int, int]

    def pack(self) -> bytes:
        return HEADER_STRUCT.pack(
            self.magic,
            self.format_version,
            self.header_bytes,
            self.hardware_abi,
            self.load_address,
            self.entry_address,
            self.payload_bytes,
            self.payload_crc32,
            self.sequence,
            self.state,
            self.header_crc32,
            *self.reserved,
        )

    @classmethod
    def unpack(cls, raw: bytes) -> "ImageHeader":
        if len(raw) != HEADER_BYTES:
            raise ImageError(f"header must contain {HEADER_BYTES} bytes, got {len(raw)}")
        fields = HEADER_STRUCT.unpack(raw)
        return cls(*fields[:11], tuple(fields[11:]))


def crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def header_crc32(header: ImageHeader) -> int:
    """CRC the header while logical state and its CRC field are zero.

    State is intentionally excluded so the bootloader can atomically change
    STAGING to COMMITTED with a final 1-to-0 User Flash word program.
    """

    raw = bytearray(header.pack())
    struct.pack_into("<I", raw, STATE_OFFSET, 0)
    struct.pack_into("<I", raw, HEADER_CRC_OFFSET, 0)
    return crc32(bytes(raw))


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ImageError(message)


def validate_header(
    header: ImageHeader,
    *,
    expected_hardware_abi: Optional[int] = None,
    accepted_states: Iterable[int] = (STATE_STAGING, STATE_COMMITTED),
) -> None:
    _require(header.magic == MAGIC, "wrong OpenMCU image magic")
    _require(header.format_version == FORMAT_VERSION, "unsupported image format")
    _require(header.header_bytes == HEADER_BYTES, "wrong image-header length")
    _require(header.load_address == APPLICATION_LOAD_ADDRESS,
             "image load address is not the OpenMCU application SRAM base")
    _require(header.entry_address == APPLICATION_LOAD_ADDRESS,
             "image entry address must be the application reset vector")
    _require(header.payload_bytes > 0, "image payload must not be empty")
    _require(header.payload_bytes <= PAYLOAD_MAX_BYTES,
             "image payload exceeds one A/B User Flash slot")
    _require((header.payload_bytes & 3) == 0,
             "image payload must be padded to a 32-bit User Flash word")
    _require(header.state in tuple(accepted_states), "image state is not accepted")
    _require(all(value == 0 for value in header.reserved),
             "reserved image-header fields must be zero")
    _require(header.header_crc32 == header_crc32(header), "image header CRC mismatch")
    if expected_hardware_abi is not None:
        _require(header.hardware_abi == expected_hardware_abi,
                 "image hardware ABI does not match the selected OpenMCU target")


def build_image(
    payload: bytes,
    *,
    sequence: int = 0,
    hardware_abi: int = DEFAULT_HARDWARE_ABI,
    load_address: int = APPLICATION_LOAD_ADDRESS,
    entry_address: int = APPLICATION_LOAD_ADDRESS,
) -> bytes:
    """Return a staging image; the bootloader owns its final sequence/state."""

    if not payload:
        raise ImageError("cannot pack an empty application binary")
    if not 0 <= sequence <= 0xFFFFFFFF:
        raise ImageError("sequence must fit in an unsigned 32-bit value")
    if not 0 <= hardware_abi <= 0xFFFFFFFF:
        raise ImageError("hardware ABI must fit in an unsigned 32-bit value")

    padded_payload = payload + (b"\xff" * ((-len(payload)) & 3))
    if len(padded_payload) > PAYLOAD_MAX_BYTES:
        raise ImageError(
            f"application image is {len(padded_payload)} bytes after padding; "
            f"the A/B slot limit is {PAYLOAD_MAX_BYTES} bytes"
        )

    header_without_crc = ImageHeader(
        magic=MAGIC,
        format_version=FORMAT_VERSION,
        header_bytes=HEADER_BYTES,
        hardware_abi=hardware_abi,
        load_address=load_address,
        entry_address=entry_address,
        payload_bytes=len(padded_payload),
        payload_crc32=crc32(padded_payload),
        sequence=sequence,
        state=STATE_STAGING,
        header_crc32=0,
        reserved=(0, 0, 0, 0, 0, 0),
    )
    header = dataclasses.replace(
        header_without_crc, header_crc32=header_crc32(header_without_crc)
    )
    validate_header(header)
    return header.pack() + padded_payload


def parse_image(
    image: bytes,
    *,
    expected_hardware_abi: Optional[int] = None,
    accepted_states: Iterable[int] = (STATE_STAGING, STATE_COMMITTED),
) -> Tuple[ImageHeader, bytes]:
    if len(image) < HEADER_BYTES:
        raise ImageError("image is shorter than its fixed header")
    header = ImageHeader.unpack(image[:HEADER_BYTES])
    validate_header(
        header,
        expected_hardware_abi=expected_hardware_abi,
        accepted_states=accepted_states,
    )
    expected_length = HEADER_BYTES + header.payload_bytes
    if len(image) != expected_length:
        raise ImageError(
            f"image length is {len(image)} bytes; header requires {expected_length} bytes"
        )
    payload = image[HEADER_BYTES:]
    if crc32(payload) != header.payload_crc32:
        raise ImageError("image payload CRC mismatch")
    return header, payload


def _parse_int(text: str) -> int:
    return int(text, 0)


def _header_as_json(header: ImageHeader, payload: bytes) -> Dict[str, object]:
    return {
        "magic": f"0x{header.magic:08x}",
        "format_version": header.format_version,
        "header_bytes": header.header_bytes,
        "hardware_abi": f"0x{header.hardware_abi:08x}",
        "load_address": f"0x{header.load_address:08x}",
        "entry_address": f"0x{header.entry_address:08x}",
        "payload_bytes": header.payload_bytes,
        "payload_crc32": f"0x{header.payload_crc32:08x}",
        "sequence": header.sequence,
        "state": f"0x{header.state:08x}",
        "header_crc32": f"0x{header.header_crc32:08x}",
        "file_bytes": HEADER_BYTES + len(payload),
    }


def _pack_command(args: argparse.Namespace) -> int:
    image = build_image(
        Path(args.input).read_bytes(),
        sequence=args.sequence,
        hardware_abi=args.hardware_abi,
    )
    Path(args.output).write_bytes(image)
    header, payload = parse_image(image, expected_hardware_abi=args.hardware_abi)
    print(json.dumps(_header_as_json(header, payload), indent=2, sort_keys=True))
    return 0


def _inspect_command(args: argparse.Namespace) -> int:
    header, payload = parse_image(
        Path(args.image).read_bytes(),
        expected_hardware_abi=args.hardware_abi,
    )
    print(json.dumps(_header_as_json(header, payload), indent=2, sort_keys=True))
    return 0


def _validate_command(args: argparse.Namespace) -> int:
    header, payload = parse_image(
        Path(args.image).read_bytes(),
        expected_hardware_abi=args.hardware_abi,
    )
    print(
        f"PASS: {args.image} is a valid {header.payload_bytes}-byte OpenMCU "
        f"application image (payload CRC 0x{header.payload_crc32:08x})"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    pack = subparsers.add_parser("pack", help="pack a raw SRAM binary as .omcu")
    pack.add_argument("--input", required=True, help="input raw application binary")
    pack.add_argument("--output", required=True, help="output .omcu image")
    pack.add_argument("--sequence", type=_parse_int, default=0,
                      help="diagnostic sequence placeholder; bootloader assigns final order")
    pack.add_argument("--hardware-abi", type=_parse_int, default=DEFAULT_HARDWARE_ABI)
    pack.set_defaults(handler=_pack_command)

    inspect = subparsers.add_parser("inspect", help="print validated image metadata")
    inspect.add_argument("--image", required=True)
    inspect.add_argument("--hardware-abi", type=_parse_int, default=None)
    inspect.set_defaults(handler=_inspect_command)

    validate = subparsers.add_parser("validate", help="validate a .omcu image")
    validate.add_argument("--image", required=True)
    validate.add_argument("--hardware-abi", type=_parse_int, default=None)
    validate.set_defaults(handler=_validate_command)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except (ImageError, OSError) as exc:
        parser.error(str(exc))
    return 2


if __name__ == "__main__":
    sys.exit(main())
