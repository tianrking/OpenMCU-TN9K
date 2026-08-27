from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


POWERSHELL = shutil.which("pwsh")
PROGRAM_SCRIPT = (
    Path(__file__).resolve().parents[2] / "scripts" / "program-tangnano9k.ps1"
)


@unittest.skipUnless(POWERSHELL, "PowerShell 7 is required")
class TangNano9kProgrammerScriptTests(unittest.TestCase):
    def _run_fake_programmer(self, output: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            bitstream = directory / "test.fs"
            bitstream.write_bytes(b"test-bitstream")
            programmer = directory / "fake-openfpgaloader.ps1"
            quoted_lines = "\n".join(
                "Write-Output '{}'".format(line.replace("'", "''"))
                for line in output.splitlines()
            )
            programmer.write_text(quoted_lines + "\nexit 0\n", encoding="utf-8")

            return subprocess.run(
                [
                    POWERSHELL,
                    "-NoProfile",
                    "-File",
                    str(PROGRAM_SCRIPT),
                    "-BitstreamPath",
                    str(bitstream),
                    "-Destination",
                    "sram",
                    "-OpenFPGALoader",
                    str(programmer),
                    "-AllowUnverifiedArtifact",
                    "-Confirm:$false",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

    def test_accepts_explicit_programmer_success(self) -> None:
        result = self._run_fake_programmer("Done\nCRC check: Success")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("openFPGALoader completed", result.stdout)

    def test_rejects_zero_exit_transport_and_verification_failures(self) -> None:
        failures = (
            "Done\nFAIL",
            "CRC check: FAIL",
            "mpsse_write: fail to write with error -1 (usb bulk write failed)",
            "Loopback failed, expect problems on later runs -1",
            "unable to config pins : -1 unable to configure bitbang mode",
        )
        for output in failures:
            with self.subTest(output=output):
                result = self._run_fake_programmer(output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("programming/USB transport failure", result.stderr)


if __name__ == "__main__":
    unittest.main()
