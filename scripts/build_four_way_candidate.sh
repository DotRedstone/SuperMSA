#!/bin/bash
# Build Huffman and native DSQDATA adapters in a fresh source checkout.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test01, not login node" >&2; exit 2 ;;
esac
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"
test -f src/msa_dsq_bridge.h
test -f scripts/fasta_to_dsqdata.c
test -f scripts/verify_dsqdata.c
test -f tests/test_dsqdata_smoke.sh
# Includes full compilation of jackhmmer and Huffman correctness tests.
bash scripts/build_huffman_candidate.sh
gcc -O3 -std=c99 -Wall -Wextra -I easel \
  -o scripts/fasta_to_dsqdata scripts/fasta_to_dsqdata.c \
  -L easel -leasel -pthread -lm \
  > dsqdata.writer-build.log 2>&1 || {
  tail -n 80 dsqdata.writer-build.log >&2; exit 1;
}
gcc -O3 -std=c99 -Wall -Wextra -I easel \
  -o scripts/verify_dsqdata scripts/verify_dsqdata.c \
  -L easel -leasel -pthread -lm \
  > dsqdata.verifier-build.log 2>&1 || {
  tail -n 80 dsqdata.verifier-build.log >&2; exit 1;
}
bash tests/test_dsqdata_smoke.sh > dsqdata.smoke.log 2>&1 || {
  tail -n 100 dsqdata.smoke.log >&2; exit 1;
}
cat dsqdata.smoke.log
sha256sum src/jackhmmer scripts/fasta_to_bin8 scripts/bin8_to_huffman \
  scripts/fasta_to_dsqdata scripts/verify_dsqdata scripts/verify_huffman \
  > four_way.binaries.sha256
echo "FOUR_WAY_BUILD_AND_SMOKE=PASS"
