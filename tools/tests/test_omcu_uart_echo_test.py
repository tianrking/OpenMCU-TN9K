import unittest

from tools import omcu_uart_echo_test


class UartEchoHostToolTests(unittest.TestCase):
    def test_block_pattern_is_deterministic_and_changes_phase(self) -> None:
        self.assertEqual(
            omcu_uart_echo_test.block_pattern(0, 4),
            bytes((19, 92, 165, 238)),
        )
        self.assertNotEqual(
            omcu_uart_echo_test.block_pattern(0, 32),
            omcu_uart_echo_test.block_pattern(1, 32),
        )

    def test_first_mismatch_handles_changed_and_short_streams(self) -> None:
        self.assertEqual(
            omcu_uart_echo_test.first_mismatch(b"abcd", b"abXd"), 2
        )
        self.assertEqual(
            omcu_uart_echo_test.first_mismatch(b"abcd", b"ab"), 2
        )
        self.assertEqual(
            omcu_uart_echo_test.first_mismatch(b"abcd", b"abcd"), 4
        )


if __name__ == "__main__":
    unittest.main()
