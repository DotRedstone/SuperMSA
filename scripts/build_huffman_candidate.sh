#!/bin/bash
# Build 8-bit baseline and Huffman candidate on test01.
set -euo pipefail
case "$(hostname)" in
  cln0[1-4]*|ibcln*) echo "ERROR: use test01, not login node" >&2; exit 2 ;;
esac
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"
test -f src/msa_huffman.h
test -f scripts/bin8_to_huffman.c
test -f tests/test_huffman_smoke.sh

# Recompile the full jackhmmer data path from this exact branch.
bash scripts/build_bin8_candidate.sh
gcc -O3 -std=c99 -Wall -Wextra \
    -o scripts/bin8_to_huffman scripts/bin8_to_huffman.c \
    > huffman.converter-build.log 2>&1 || {
      tail -n 100 huffman.converter-build.log >&2
      exit 1
    }
bash tests/test_huffman_smoke.sh > huffman.smoke.log 2>&1 || {
    tail -n 120 huffman.smoke.log >&2
    exit 1
}
cat huffman.smoke.log
sha256sum src/jackhmmer scripts/fasta_to_bin8 scripts/bin8_to_huffman \
    > huffman.binaries.sha256
echo "HUFFMAN_BUILD_AND_SMOKE=PASS"
