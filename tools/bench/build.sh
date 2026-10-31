#!/bin/bash
# 在测试节点编译一个 commit：tools/bench/build.sh <ref> [<ref> ...]
# 产物：$MSA_WS/experiments/supermsa/builds/<sha12>/，同一个 commit 只编译一次。
# 如果该 commit 中有 tools/bench/build_hook.sh（例如编译预处理转换器），会在 make 之后执行。
# BINARIES.sha256 最后写入，它存在即表示编译、冒烟测试和 hook 全部通过。
set -euo pipefail

case $(hostname) in
    cln0[1-4]*|ibcln*) echo "ERROR: 登录节点禁止编译，请先 ssh test01" >&2; exit 1;;
esac

WS=${MSA_WS:-$HOME/WORK/dot}
REPO=${MSA_REPO:-$WS/SuperMSA}
BUILDS=$WS/experiments/supermsa/builds
[ $# -ge 1 ] || { echo "usage: $0 <ref> [<ref> ...]" >&2; exit 2; }

# 集群上的 git 是 1.8.3，不支持 git -C；分支名找不到时自动尝试 origin/<分支名>。
g() { (cd "$REPO" && git "$@"); }
resolve_sha() {
    g rev-parse -q --verify "$1^{commit}" 2>/dev/null || g rev-parse -q --verify "origin/$1^{commit}" 2>/dev/null
}

for ref in "$@"; do
    sha=$(resolve_sha "$ref") || { echo "ERROR: 无法解析 $ref（先在本地 push 并执行 tools/bench/sync_hpc.sh）" >&2; exit 1; }
    dir=$BUILDS/${sha:0:12}
    if [ -f "$dir/BINARIES.sha256" ]; then
        echo "BUILD_OK $ref ${sha:0:12} (cached)"; continue
    fi
    [ ! -e "$dir" ] || { echo "ERROR: $dir 是未完成的编译，删除后重试" >&2; exit 1; }

    mkdir -p "$dir"
    g archive "$sha" | tar -x -m -C "$dir"   # -m：不还原 commit 时间戳，避免时钟偏差干扰 make
    (
        cd "$dir"
        autoconf
        ./configure
        make -j"$(nproc)"
        ./smoke_test.sh
        [ ! -f tools/bench/build_hook.sh ] || bash tools/bench/build_hook.sh
    ) > "$dir/build.log" 2>&1 || {
        tail -n 30 "$dir/build.log" >&2
        echo "ERROR: $ref 编译失败，日志：$dir/build.log" >&2
        exit 1
    }
    {
        echo "commit=$sha"
        echo "ref=$ref"
        echo "built_at=$(date -Is)"
        echo "built_on=$(hostname)"
        echo "compiler=$(gcc --version | head -n1)"
    } > "$dir/BUILD_INFO"
    (cd "$dir" && find src/jackhmmer scripts -maxdepth 1 -type f -perm -u+x 2>/dev/null \
        | sort | xargs sha256sum) > "$dir/BINARIES.sha256.tmp"
    mv "$dir/BINARIES.sha256.tmp" "$dir/BINARIES.sha256"
    echo "BUILD_OK $ref ${sha:0:12}"
done
