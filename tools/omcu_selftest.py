#!/usr/bin/env python3
"""Program and qualify the OpenMCU-TN9K no-fixture board self-test image."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable, List, Optional, Set


EXPECTED_PASSES = frozenset(
    {
        "HW_IDENTITY",
        "FEATURES",
        "MEMORY_GEOMETRY",
        "BOOTLOADER_REQUEST_CAPABILITY",
        "WDT_RESET",
        "SRAM_16K",
        "RV32IM",
        "SYSCTRL_TICKS",
        "GPIO_PAD_READBACK",
        "GPIO_RELIABILITY_MMIO",
        "IRQCTRL_FORCE",
        "TIMER0_COMPARE",
        "ALARM0_COMPARE",
        "PWM0_TIMEBASE",
        "PWM1_PAD_READBACK",
        "TIMER1_COMPARE",
        "UART1_TX_PAD",
        "SPI0_ENGINE_IDLE_MISO",
        "I2C0_IDLE_START_STOP",
        "PINMUX_MMIO",
        "PULSE0_MMIO",
        "FAULT0_MMIO",
        "WDT_SUPERVISOR",
        "UART0_RX",
    }
)

LOOPBACK_EXPECTED_PASSES = frozenset(
    {
        "HARDWARE_CAPABILITIES",
        "HARNESS_GPIO",
        "UART1_LOOPBACK",
        "SPI0_LOOPBACK",
        "TIMER1_ENCODER_LOOPBACK",
        "PWM1_TIMER1_LOOPBACK",
        "PWM0_PULSE0_LOOPBACK",
        "FAULT0_GPIO_GATE_LOOPBACK",
    }
)


class SelftestError(RuntimeError):
    """The target did not produce a complete passing self-test transcript."""


class TranscriptEvaluator:
    def __init__(self, expected: Iterable[str] = EXPECTED_PASSES) -> None:
        self.expected: Set[str] = set(expected)
        self.passed: Set[str] = set()
        self.failed: List[str] = []
        self.ready_for_ping = False
        self.result_line: Optional[str] = None

    def accept(self, line: str) -> None:
        normalized = line.strip()
        if normalized.startswith("PASS "):
            self.passed.add(normalized[5:])
        elif normalized.startswith("FAIL "):
            self.failed.append(normalized[5:])
        elif normalized == "READY UART0_RX":
            self.ready_for_ping = True
        elif normalized.startswith("RESULT "):
            self.result_line = normalized

    def validate(self) -> None:
        missing = sorted(self.expected - self.passed)
        unexpected = sorted(self.passed - self.expected)
        errors: List[str] = []
        if self.failed:
            errors.append("target FAIL: " + ", ".join(self.failed))
        if missing:
            errors.append("missing PASS: " + ", ".join(missing))
        if unexpected:
            errors.append("unexpected PASS: " + ", ".join(unexpected))
        if self.result_line is None:
            errors.append("missing RESULT line")
        elif not self.result_line.startswith("RESULT PASS "):
            errors.append(self.result_line)
        if errors:
            raise SelftestError("; ".join(errors))


def program_image(port: str, image: Path, baud: int, connect_timeout: float) -> None:
    flash_tool = Path(__file__).with_name("omcu_flash.py")
    command = [
        sys.executable,
        str(flash_tool),
        "--port",
        port,
        "--image",
        str(image),
        "--baud",
        str(baud),
        "--connect-timeout",
        str(connect_timeout),
    ]
    print("Programming self-test image; press RESET while Bootloader discovery is active.")
    subprocess.run(command, check=True)


def capture_selftest(
    port: str,
    *,
    baud: int,
    timeout: float,
    log_path: Optional[Path],
    expected: Iterable[str],
) -> TranscriptEvaluator:
    try:
        import serial  # type: ignore
    except ModuleNotFoundError as exc:
        raise SelftestError(
            "missing pyserial; run `python -m pip install pyserial`"
        ) from exc

    evaluator = TranscriptEvaluator(expected)
    transcript: List[str] = []
    pending = bytearray()
    ping_sent = False
    deadline = time.monotonic() + timeout

    with serial.Serial(
        port=port,
        baudrate=baud,
        timeout=0.05,
        write_timeout=2.0,
    ) as connection:
        while time.monotonic() < deadline:
            chunk = connection.read(256)
            if chunk:
                pending.extend(chunk)
                while b"\n" in pending:
                    raw_line, _, remainder = pending.partition(b"\n")
                    pending = bytearray(remainder)
                    line = raw_line.rstrip(b"\r").decode("ascii", errors="replace")
                    transcript.append(line)
                    print(line)
                    evaluator.accept(line)
                    if evaluator.ready_for_ping and not ping_sent:
                        connection.write(b"PING\r\n")
                        # Do not call pyserial.flush()/POSIX tcdrain here.
                        # AppleUSBFTDI can block in tcdrain indefinitely after
                        # a Tang board power cycle; write_timeout plus the
                        # request/response ordering is sufficient.
                        ping_sent = True
                    if evaluator.result_line is not None:
                        if log_path is not None:
                            log_path.parent.mkdir(parents=True, exist_ok=True)
                            log_path.write_text("\n".join(transcript) + "\n", encoding="utf-8")
                        evaluator.validate()
                        return evaluator

    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("\n".join(transcript) + "\n", encoding="utf-8")
    raise SelftestError(f"timed out after {timeout:g}s waiting for RESULT")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--image", type=Path,
                        help="program this .omcu before capturing the test")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=30.0,
                        help="seconds allowed for WDT reboot and all checks")
    parser.add_argument("--connect-timeout", type=float, default=12.0,
                        help="Bootloader discovery timeout when --image is used")
    parser.add_argument("--log", type=Path, help="save the raw line transcript")
    parser.add_argument("--profile", choices=("core", "loopback"), default="core",
                        help="expected firmware transcript (default: core)")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.baud <= 0 or args.timeout <= 0.0 or args.connect_timeout <= 0.0:
        parser.error("baud and timeouts must be positive")
    if args.image is not None:
        if not args.image.is_file():
            parser.error(f"missing image: {args.image}")
        try:
            program_image(args.port, args.image, args.baud, args.connect_timeout)
        except subprocess.CalledProcessError as exc:
            parser.error(f"application programming failed with exit code {exc.returncode}")
    try:
        expected = (EXPECTED_PASSES if args.profile == "core" else
                    LOOPBACK_EXPECTED_PASSES)
        evaluator = capture_selftest(
            args.port,
            baud=args.baud,
            timeout=args.timeout,
            log_path=args.log,
            expected=expected,
        )
    except (OSError, SelftestError) as exc:
        parser.error(str(exc))
    print(f"PASS: OpenMCU {args.profile} self-test "
          f"{len(evaluator.passed)}/{len(expected)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
