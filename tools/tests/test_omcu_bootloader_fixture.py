import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import omcu_bootloader_fixture


class BootloaderFixtureTests(unittest.TestCase):
    def _write(self, directory: Path, name: str, text: str) -> Path:
        path = directory / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_ignores_line_endings_and_whitespace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            generated = self._write(directory, "generated.hex", "@00000000\n00AA 00bb\n")
            fixture = self._write(directory, "fixture.hex", "  @00000000\r\n00aa    00BB\r\n")
            omcu_bootloader_fixture.verify_fixture(generated, fixture)

    def test_reports_a_stale_token(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            generated = self._write(directory, "generated.hex", "@0\n00000013\n")
            fixture = self._write(directory, "fixture.hex", "@0\n00000000\n")
            with self.assertRaises(omcu_bootloader_fixture.FixtureError):
                omcu_bootloader_fixture.verify_fixture(generated, fixture)
