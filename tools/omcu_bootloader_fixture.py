#!/usr/bin/env python3
"""Check that the vendor-project Boot ROM fixture matches a built bootloader."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Iterable, List, Optional


class FixtureError(ValueError):
    """A checked-in Verilog memory image is malformed or stale."""


def normalized_verilog_tokens(text: str) -> List[str]:
    """Return formatting-independent tokens from a GNU objcopy Verilog image."""

    tokens: List[str] = []
    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        for token in line.split():
            if token.startswith("@"):
                value = token[1:]
            else:
                value = token
            if not value or any(character not in "0123456789abcdefABCDEF" for character in value):
                raise FixtureError("invalid Verilog-memory token: {}".format(token))
            tokens.append(token.upper())
    if not tokens:
        raise FixtureError("Verilog-memory image contains no tokens")
    return tokens


def verify_fixture(generated: Path, fixture: Path) -> None:
    expected = normalized_verilog_tokens(generated.read_text(encoding="utf-8"))
    actual = normalized_verilog_tokens(fixture.read_text(encoding="utf-8"))
    if actual == expected:
        return
    limit = min(len(actual), len(expected))
    index = next((item for item in range(limit) if actual[item] != expected[item]), limit)
    expected_token = expected[index] if index < len(expected) else "<end>"
    actual_token = actual[index] if index < len(actual) else "<end>"
    raise FixtureError(
        "checked-in Boot ROM fixture is stale at token {}: fixture={}, generated={}. "
        "Regenerate rtl/platform/tangnano9k/firmware/bootloader.hex from the "
        "verified omcu_bootloader.hex before releasing a vendor project.".format(
            index, actual_token, expected_token
        )
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", required=True, type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    return parser


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        verify_fixture(args.generated, args.fixture)
    except (FixtureError, OSError) as exc:
        print("ERROR: {}".format(exc), file=sys.stderr)
        return 2
    print("PASS: checked-in Boot ROM fixture matches {}".format(args.generated))
    return 0


if __name__ == "__main__":
    sys.exit(main())
