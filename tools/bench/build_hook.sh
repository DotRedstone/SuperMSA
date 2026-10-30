#!/bin/bash
# DP-01/V04：在 demo 数据和边界样例上验证 4K 与 64K 读取块逐字节一致。
set -euo pipefail
bash tests/test_fasta_read_chunk.sh
