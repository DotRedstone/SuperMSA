#!/bin/bash
# main（v2）：bin8 冒烟测试；DP-01/V04：4K 与 64K 读取块逐字节一致。
set -euo pipefail
bash tests/test_bin8_smoke.sh
bash tests/test_fasta_read_chunk.sh
