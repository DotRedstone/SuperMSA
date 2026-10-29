#!/bin/bash
# Run only on test01/test nodes; build each variant in its own source tree.
# Suggested: module load compilers/gcc/v12.2.0
set -euo pipefail

case "$(hostname)" in
    cln0[1-4]*|ibcln*) echo "ERROR: do not compile on login node" >&2; exit 1 ;;
esac

ROOT="${WORK_ROOT:-$HOME/WORK/dot}"
SOURCE="$ROOT/SuperMSA"
OUT="${SSV_OUT:-$ROOT/experiments/supermsa/probes/ssv-band-build-r01}"

command -v rsync >/dev/null
command -v make >/dev/null
command -v gcc >/dev/null
test -f "$SOURCE/src/impl_sse/ssvfilter.c"
grep -q '^#define SSV_BAND_LIMIT MAX_BANDS$' "$SOURCE/src/impl_sse/ssvfilter.c" ||
    { echo "ERROR: SSV_BAND_LIMIT patch is not present in SOURCE" >&2; exit 1; }
test -x "$SOURCE/configure" || { echo "ERROR: configure is missing; generate it on test node first" >&2; exit 1; }
test ! -e "$OUT" || { echo "ERROR: output exists ($OUT); use a new SSV_OUT to keep prior builds immutable" >&2; exit 1; }
mkdir -p "$OUT/bin"
gcc --version | head -n 1 > "$OUT/compiler.txt"

for band in 14 12 10 8; do
    echo "=== Building SSV_BAND_LIMIT=$band ==="
    variant="$OUT/band-$band"
    build="$variant/source"
    mkdir -p "$build"
    rsync -a \
        --exclude='.git/' \
        --exclude='results/' \
        --exclude='autom4te.cache/' \
        --exclude='*.o' \
        --exclude='src/jackhmmer' \
        "$SOURCE/" "$build/"
    file="$build/src/impl_sse/ssvfilter.c"
    if [ "$band" != 14 ]; then
        sed -i "s/^#define SSV_BAND_LIMIT MAX_BANDS$/#define SSV_BAND_LIMIT $band/" "$file"
    fi
    grep -q "^#define SSV_BAND_LIMIT \(MAX_BANDS\|$band\)$" "$file"

    (
        cd "$build"
        ./configure > "$variant/configure.log" 2>&1
        make clean > "$variant/clean.log" 2>&1
        make -j8 > "$variant/make.log" 2>&1
        ./smoke_test.sh > "$variant/smoke.log" 2>&1
    )
    grep -q '^PASS:' "$variant/smoke.log" ||
        { echo "ERROR: smoke test failed for band $band" >&2; exit 1; }
    cp -p "$build/src/jackhmmer" "$OUT/bin/jackhmmer-band-$band"
    sha256sum "$OUT/bin/jackhmmer-band-$band" >> "$OUT/binaries.sha256"
    echo "PASS: band=$band, saved $OUT/bin/jackhmmer-band-$band"
done

echo "ALL_VARIANTS_BUILT=YES"
echo "BIN_DIR=$OUT/bin"
