#!/bin/bash
# DP-02/V02-bin8：编译 FASTA→BIN8 转换器，并在玩具库上验证 raw 与 bin8 的输出一致。
set -euo pipefail
gcc -O3 -std=c99 -Wall -Wextra -I easel -o scripts/fasta_to_bin8 scripts/fasta_to_bin8.c \
    -L easel -leasel -pthread -lm
bash tests/test_bin8_smoke.sh
