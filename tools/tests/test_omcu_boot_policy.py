from __future__ import annotations

import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


HOST_CC = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(HOST_CC, "a host C compiler is required")
class BootloaderUpdatePolicyTests(unittest.TestCase):
    def test_page_scope(self) -> None:
        source = textwrap.dedent(
            """
            #include "omcu_boot_policy.h"
            #include <assert.h>

            int main(void) {
              assert(omcu_boot_erase_pages_for_payload(1u) == 1u);
              assert(omcu_boot_erase_pages_for_payload(1984u) == 1u);
              assert(omcu_boot_erase_pages_for_payload(1988u) == 2u);
              assert(omcu_boot_erase_pages_for_payload(
                       OMCU_IMAGE_PAYLOAD_MAX_BYTES) == OMCU_IMAGE_SLOT_PAGES);

              return 0;
            }
            """
        )
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source_path = directory / "boot_policy_test.c"
            executable = directory / "boot_policy_test"
            source_path.write_text(source, encoding="utf-8")
            compile_result = subprocess.run(
                [
                    HOST_CC,
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-I",
                    str(REPOSITORY_ROOT / "sdk" / "include"),
                    "-I",
                    str(REPOSITORY_ROOT / "sdk" / "bootloader"),
                    str(source_path),
                    "-o",
                    str(executable),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                compile_result.returncode,
                0,
                compile_result.stdout + compile_result.stderr,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()
