#!/bin/bash
# main（v2）：bin8 冒烟测试；DP-01/V01+V02：单遍解析和直接映射与原路径逐字节一致。
set -euo pipefail
bash tests/test_bin8_smoke.sh
gcc -O2 -std=c99 -Wall -I easel -o tests/fasta_dump tests/fasta_dump.c -L easel -leasel -pthread -lm
bash tests/test_fasta_onepass.sh
bash tests/test_fasta_direct_map.sh
