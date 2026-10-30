#!/bin/bash
# DP-01：编译测试辅助工具，并在 demo 数据上验证新读取路径与原路径逐字节一致。
set -euo pipefail
gcc -O2 -std=c99 -Wall -I easel -o tests/fasta_dump tests/fasta_dump.c -L easel -leasel -pthread -lm
bash tests/test_fasta_onepass.sh
bash tests/test_fasta_direct_map.sh
