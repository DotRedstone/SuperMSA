#!/bin/bash
# DP-03/V02：多线程、多轮迭代下比较 broadcast 与 signal-one 的输出，并用 timeout 防止死锁。
set -euo pipefail
bash tests/test_queue_signal_one.sh
