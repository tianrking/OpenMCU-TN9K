#!/usr/bin/env python3
"""Validate the machine-readable Tang Nano 9K header/CST/SDK contract."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PINMAP_PATH = ROOT / "spec" / "tangnano9k-pins.json"
CST_PATH = (
    ROOT
    / "rtl"
    / "platform"
    / "tangnano9k"
    / "project"
    / "omcu_tn9k_bringup.cst"
)
SDK_PATH = ROOT / "sdk" / "include" / "omcu_tn9k.h"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    pinmap = json.loads(PINMAP_PATH.read_text(encoding="utf-8"))
    headers = pinmap["headers"]
    profile = pinmap["mcu_profile"]

    expected_order = [f"L{i}" for i in range(1, 25)] + [
        f"R{i}" for i in range(1, 25)
    ]
    require(
        [entry["designator"] for entry in headers] == expected_order,
        "pin map must contain L1..L24 then R1..R24 exactly once",
    )

    package_pins = [
        entry["package_pin"]
        for entry in headers
        if entry["package_pin"] is not None
    ]
    require(
        len(package_pins) == len(set(package_pins)),
        "a package pin is assigned to more than one header position",
    )
    known_statuses = set(pinmap["status_definitions"])
    require(
        all(entry["status"] in known_statuses for entry in headers),
        "a header position uses an undefined publication status",
    )

    public = [
        entry for entry in headers if entry["status"] == "public-mcu-signal"
    ]
    require(
        len(public) == profile["public_header_signal_count"] == 19,
        "public MCU signal count must remain 19",
    )
    require(
        [entry["designator"] for entry in public] == [f"L{i}" for i in range(1, 20)],
        "ABI 0.9 public signals must be the contiguous physical L1..L19 group",
    )
    for entry in public:
        require(entry["voltage"] == 3.3, f"{entry['designator']} is not 3.3 V")
        require(entry.get("cst_port"), f"{entry['designator']} lacks a CST port")
        require(
            "HDMI" not in (entry.get("board_net") or ""),
            f"{entry['designator']} incorrectly publishes an HDMI-shared net",
        )

    for entry in headers:
        if entry["status"] == "excluded-1v8":
            require(
                entry["voltage"] == 1.8 and entry["bank"] == 3,
                f"{entry['designator']} must be a Bank-3 1.8 V exclusion",
            )
        if entry["status"] == "excluded-hdmi-pulled":
            require(
                "HDMI" in (entry.get("board_net") or ""),
                f"{entry['designator']} HDMI exclusion lacks an HDMI net",
            )
        if entry["status"] == "reserved-3v3":
            require(
                entry["voltage"] == 3.3 and not entry.get("cst_port"),
                f"{entry['designator']} reserved pin must be 3.3 V and unpublished",
            )
        if entry["status"] == "power":
            require(
                entry["package_pin"] is None and entry["bank"] is None,
                f"{entry['designator']} power position cannot be an FPGA I/O",
            )

    gpio_entries = [entry for entry in public if "logical_gpio" in entry]
    require(
        [entry["logical_gpio"] for entry in gpio_entries] == list(range(12)),
        "logical GPIO0..11 must map in order to L8..L19",
    )
    require(profile["public_gpio_count"] == 12, "public GPIO count must be 12")
    require(
        int(profile["public_gpio_mask"], 0) == (1 << 12) - 1,
        "public GPIO mask must cover exactly GPIO0..11",
    )

    cst_text = CST_PATH.read_text(encoding="utf-8")
    cst_locations = {
        port: int(pin)
        for port, pin in re.findall(r'IO_LOC\s+"([^"]+)"\s+(\d+)\s*;', cst_text)
    }
    for entry in public:
        port = entry["cst_port"]
        require(port in cst_locations, f"CST is missing {port}")
        require(
            cst_locations[port] == entry["package_pin"],
            f"{port} maps to package {cst_locations[port]}, expected {entry['package_pin']}",
        )
        io_port_pattern = rf'IO_PORT\s+"{re.escape(port)}"[^;]*IO_TYPE=LVCMOS33'
        require(
            re.search(io_port_pattern, cst_text) is not None,
            f"{port} is not explicitly constrained as LVCMOS33",
        )

    sdk_text = SDK_PATH.read_text(encoding="utf-8")
    require(
        re.search(r"#define\s+OMCU_TN9K_GPIO_COUNT\s+12u\b", sdk_text) is not None,
        "SDK GPIO_COUNT definition is missing or wrong",
    )
    require(
        re.search(
            r"#define\s+OMCU_TN9K_GPIO_MASK\s+UINT32_C\(0x00000FFF\)",
            sdk_text,
        )
        is not None,
        "SDK GPIO_MASK definition is missing or wrong",
    )
    physical_macros = {
        "OMCU_TN9K_PUBLIC_HEADER_SIGNAL_COUNT": 19,
        "OMCU_TN9K_SPI0_CS_L": 1,
        "OMCU_TN9K_SPI0_MOSI_L": 2,
        "OMCU_TN9K_SPI0_SCK_L": 3,
        "OMCU_TN9K_SPI0_MISO_L": 4,
        "OMCU_TN9K_PWM0_L": 5,
        "OMCU_TN9K_I2C0_SCL_L": 6,
        "OMCU_TN9K_I2C0_SDA_L": 7,
        "OMCU_TN9K_GPIO_FIRST_L": 8,
        "OMCU_TN9K_GPIO_LAST_L": 19,
        "OMCU_TN9K_UART1_TX_L": 18,
        "OMCU_TN9K_UART1_RX_L": 19,
        "OMCU_TN9K_5V_R": 18,
        "OMCU_TN9K_GND_R": 23,
        "OMCU_TN9K_3V3_R": 24,
    }
    for macro, value in physical_macros.items():
        require(
            re.search(rf"#define\s+{macro}\s+{value}u\b", sdk_text) is not None,
            f"SDK physical definition {macro} is missing or wrong",
        )
    for entry in gpio_entries:
        alias = entry["designator"]
        gpio = entry["logical_gpio"]
        pattern = rf"#define\s+OMCU_TN9K_{alias}_GPIO\s+OMCU_TN9K_GPIO{gpio}\b"
        require(
            re.search(pattern, sdk_text) is not None,
            f"SDK physical alias OMCU_TN9K_{alias}_GPIO is missing or wrong",
        )

    print(
        "PASS: Tang Nano 9K pin contract covers all 48 header positions, "
        "19 public 3.3 V MCU signals and GPIO0..11 on physical L8..L19"
    )


if __name__ == "__main__":
    main()
