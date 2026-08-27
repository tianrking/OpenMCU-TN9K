from __future__ import annotations

import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import omcu_selftest  # noqa: E402


class OpenMcuSelftestTranscriptTests(unittest.TestCase):
    def test_complete_transcript_is_accepted(self) -> None:
        evaluator = omcu_selftest.TranscriptEvaluator({"ONE", "TWO"})
        evaluator.accept("PASS ONE")
        evaluator.accept("READY UART0_RX")
        evaluator.accept("PASS TWO")
        evaluator.accept("RESULT PASS pass=2 fail=0")
        evaluator.validate()
        self.assertTrue(evaluator.ready_for_ping)

    def test_missing_or_failed_checks_are_rejected(self) -> None:
        evaluator = omcu_selftest.TranscriptEvaluator({"ONE", "TWO"})
        evaluator.accept("PASS ONE")
        evaluator.accept("FAIL BUS")
        evaluator.accept("RESULT FAIL pass=1 fail=1")
        with self.assertRaisesRegex(omcu_selftest.SelftestError, "BUS"):
            evaluator.validate()


if __name__ == "__main__":
    unittest.main()
