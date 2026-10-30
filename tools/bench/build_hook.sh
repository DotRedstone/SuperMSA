#!/bin/bash
# DP-02/V02-bin8：编译 FASTA→BIN8 转换器，并在玩具库上验证 raw 与 bin8 的输出一致。
set -euo pipefail
gcc -O3 -std=c99 -Wall -Wextra -I easel -o scripts/fasta_to_bin8 scripts/fasta_to_bin8.c \
    -L easel -leasel -pthread -lm
bash tests/test_bin8_smoke.sh
# DP-02/V04：编译 DSQDATA 转换器和校验器，验证往返无损以及与 raw 输出一致。
for t in fasta_to_dsqdata verify_dsqdata; do
    gcc -O3 -std=c99 -Wall -Wextra -I easel -o scripts/$t scripts/$t.c -L easel -leasel -pthread -lm
done
bash tests/test_dsqdata_smoke.sh
