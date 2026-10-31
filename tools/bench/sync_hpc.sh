#!/usr/bin/env bash
# 在本地运行：把 GitHub 上的状态通过 ssh 同步到集群仓库，并把集群上的 main 快进。
# 集群访问 GitHub 不稳定，所以由本地推送。推送的是 origin/*（已经推到 GitHub 的内容），
# 不是本地未推送的分支，这样集群上运行的代码一定能在 GitHub 上找到。
#   tools/bench/sync_hpc.sh            # 先 git push，再执行它
set -euo pipefail

HPC=${MSA_HPC:-thuscc26team39@192.168.11.1}
DEST=${MSA_HPC_REPO:-WORK/dot/SuperMSA}   # 相对于集群上的 home

git fetch -q --prune origin
git push -q --prune "$HPC:$DEST" \
    '+refs/remotes/origin/*:refs/remotes/origin/*' '+refs/tags/*:refs/tags/*'
ssh -o BatchMode=yes "$HPC" "cd $DEST && { git rev-parse -q --verify refs/heads/main >/dev/null || git checkout -q -b main origin/main; } \
    && git checkout -q main && git merge -q --ff-only origin/main && echo \"HPC main = \$(git log --oneline -1)\"" \
    2>&1 | grep -v -e 'post-quantum' -e 'store now' -e 'upgraded' -e 'Disk quotas' -e 'Filesystem' -e '/WORK ' -e 'no record'
