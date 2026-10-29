#!/bin/bash
# Build this candidate in a *fresh snapshot* on test01 (not login node).
set -euo pipefail

case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: compilation forbidden on login node" >&2; exit 2 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
test -f src/msa_bin8.h
test -f scripts/fasta_to_bin8.c
test -f tests/test_bin8_smoke.sh
command -v gcc
command -v make
command -v autoconf

autoconf > bin8.autoconf.log 2>&1
./configure > bin8.configure.log 2>&1
make -j8 > bin8.make.log 2>&1
gcc -O3 -std=c99 -Wall -Wextra \
    -I easel -o scripts/fasta_to_bin8 scripts/fasta_to_bin8.c \
    -L easel -leasel -pthread -lm \
    > bin8.packer-build.log 2>&1

bash tests/test_bin8_smoke.sh > bin8.smoke.log 2>&1 || {
    cat bin8.smoke.log >&2
    exit 1
}
cat bin8.smoke.log
sha256sum src/jackhmmer scripts/fasta_to_bin8 > bin8.binaries.sha256
echo "BIN8_BUILD_AND_SMOKE=PASS"
