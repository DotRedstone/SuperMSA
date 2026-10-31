# 工作规范

规矩只写在这一份文件里。要改规矩，先改这份文件。

## 1. 编号

| 层级 | 格式 | 含义 | 例 |
|---|---|---|---|
| 任务 Task | `<领域>-<NN>` | 一个组件或一个问题 | `DP-02` 预处理数据库格式 |
| 方案 Variant | `V<NN>-<slug>` | 针对该任务的一项具体改动 | `V02-bin8` |
| 运行 Run | `r<NN>-q<查询数>` | 一次 Slurm 提交 | `r01-q100` |

领域：`DP` 数据通路 · `CK` 计算核心 · `QS` 查询调度 · `SA` 搜索算法 · `EV` 评测与诊断。

- `V00` 保留给同一任务内的多方案对比或基线测量，不对应代码改动。
- 编号一经登记就**永不复用、永不改名**。
- **先在 [`EXPERIMENTS.md`](EXPERIMENTS.md) 登记，再开分支。**

## 2. 分支、tag 与 commit

| 引用 | 格式 | 例 |
|---|---|---|
| 主线 | `main`：当前最优、已验证、随时可以提交比赛 | |
| 方案分支 | `<feat\|perf\|fix\|probe>/<task>/<variant>`，全部小写 | `perf/dp-02/v02-bin8` |
| 杂务分支 | `<docs\|refactor\|chore\|fix\|test>/<slug>` | `refactor/bench-harness` |
| 发布 | tag `vN`：main 每接受一个方案，就递增一次；只修正默认值或测评工具时用 `vN.M` | `v1`、`v2.1` |
| 归档 | tag `archive/<task>/<variant>` | `archive/dp-02/v01-rewrap` |

- 方案分支**从 main 开**。如果确实依赖另一个未合并的方案，就从那个方案的分支开，并在登记表的"依赖"列写明。依赖的方案被拒绝时，本方案也要重新评估。
- 结束时：accepted → 先在分支上把开关改成**默认开启**，并确保正式的 `make` 能编译出所有需要的程序（正式评测不会设置任何环境变量），然后 `git merge --no-ff` 进 main，打 `vN`，删除分支；rejected / inconclusive / parked → 打 `archive/...` tag，删除分支。
  `parked` 表示没有测量就暂缓（写明理由），以后可以从 archive tag 恢复。
  远端只保留 main 和**进行中**的方案分支。
- commit：`<type>(<scope>): <描述>`。type ∈ `feat perf fix test docs build refactor chore`，scope 优先写领域（`dp ck qs sa ev`）。描述用中文或英文都可以。

## 3. 方案分支里放什么

- 代码改动 + 测试 + 一页说明 `docs/variants/<TASK>-<VNN>-<slug>.md`，包括：假设、改动、开关、正确性依据、运行结果、结论。
- 新行为一律用开关控制，**默认关闭**：环境变量 `MSA_<NAME>=1`。这样同一个 build 就能跑 ABBA 的两个臂。
  开关只在打开文件或创建对象时读取一次，**不要在每条记录的热路径里调用 `getenv`**，否则开关本身的开销会混进测量结果。
- 如果需要额外编译工具（例如预处理转换器），写在 `tools/bench/build_hook.sh` 里，`build.sh` 会自动执行它。
- **不放**专用的 sweep 脚本、Slurm 作业、runbook、手抄的日志。测评一律用 `tools/bench/`。

## 4. 评测标准

1. **正确性门槛**（不满足就不看时间）：每个 trial 的 `score.py` 全部 correct（ROC10 ≥ 基线的 90%），
   并且命中表与第 1 个 trial 等价（`compare_hit_tables.py`：目标集合必须完全一致，分数和 E 值只允许打印精度级别的漂移）。
2. **对照**：同一个独占节点，ABBA 顺序，同一个 build，只用开关切换。总时间 = prologue + search。
3. **接受**必须用 `q100`。`q12` 的墙钟由最慢的一条查询（Q969Q1_1）决定，只适合做快速冒烟和粗筛；**DP 类方案直接用 q100**（bin8 在 q12 上 −14%，在 q100 上 −56%）。
4. **判定**：两组配对差值同号才能判 faster / slower，否则判 inconclusive。
   如果方案**只可能影响 prologue**（例如只改 bin8 转换时用到的读取路径），**而且在提交运行之前就已经在说明文档里写明了这一点**，
   就以 prologue 时间的两组配对作为判定依据。这时 search 的差异是纯噪声，两次 base 之间的漂移常常有 20–30 s。
5. **发布与提交**：每个 `vN` 发布、每次向组委会提交之前，都要用 `new_run.sh --task EV-00 --variant V00-main --base main --order A --queries q100 --official` 复验一次。
   `--official` 不传任何资源参数，走的是正式入口的默认值。测评工具平时显式传的参数，可能会掩盖默认值配错的问题（v2 之前 `PARALLEL` 的默认值一直是 1）。

## 5. 集群

```
~/WORK/dot/
  preliminary/                         比赛数据，只读
  SuperMSA/                            仓库，只通过本地的 tools/bench/sync_hpc.sh 更新，不在这里改代码，也不在这里编译
  experiments/supermsa/
    builds/<sha12>/                    按 commit 编译的产物，只读；BINARIES.sha256 存在即表示编译完整
    <dp|ck|qs|sa|ev>/<TASK>/<VARIANT>/<RUN>/
        run.env  run.json  queries.txt  summary.tsv  report.txt  slurm-<job>.out  trials/
    legacy/                            规范建立之前的所有实验，只读
```

运行目录**只写一次**：失败了就开新的 rNN，绝不在原目录里重跑。

### 一次实验的完整流程

集群访问 GitHub 不稳定，所以由本地通过 ssh 推送：`tools/bench/sync_hpc.sh` 会把 **GitHub 上的状态**（`origin/*` 和 tag）
推到集群仓库，并把集群上的 main 快进。集群上永远不改代码。集群的 git 是 1.8.3；
`build.sh` 和 `new_run.sh` 收到分支名时，会自动解析成 `origin/<分支名>`。

```bash
# 本地
git push origin main perf/dp-02/v02-bin8
tools/bench/sync_hpc.sh

# test01：编译（同一个 commit 只编译一次）
ssh test01
module load compilers/gcc/v12.2.0
~/WORK/dot/SuperMSA/tools/bench/build.sh main perf/dp-02/v02-bin8
exit

# 登录节点：建运行目录并提交作业（先加 --dry-run 看一眼）
~/WORK/dot/SuperMSA/tools/bench/new_run.sh --task DP-02 --variant V02-bin8 \
    --tuned perf/dp-02/v02-bin8 --tuned-env 'MSA_BIN8=1' --queries q100

# 作业结束后
cat ~/WORK/dot/experiments/supermsa/dp/DP-02/V02-bin8/r01-q100/report.txt
```

结论写回 `EXPERIMENTS.md` 和该方案的 `docs/variants/` 说明。

### 向榜单提交

提交的是正式入口 `job_baseline.slurm` 生成的日志 `stdout.<作业号>`（测评工具的日志格式不同，不能提交）。

```bash
# 登录节点：用已编译的 main 跑一遍正式入口（只设置 DATA/OUT，其他全部用默认值）
SHA=<main 的 sha12>
RUN=~/WORK/dot/experiments/supermsa/ev/EV-00/V00-main/rNN-official
mkdir -p $RUN && cd $RUN && echo "commit=$SHA" > COMMIT
DATA=~/WORK/dot/preliminary OUT=$RUN/results sbatch ~/WORK/dot/experiments/supermsa/builds/$SHA/job_baseline.slurm

# 跑完后检查：并发数 6、incorrect = 0 / 100
grep -E 'prologue time|并发数|search time|mean ROC10|incorrect' stdout.*

# 在 ~/WORK/dot 下提交（凭据文件在这里），题目名是 SUPERMSA
cd ~/WORK/dot
./submit.sh --dry SUPERMSA <日志路径>    # 只校验，不计成绩
./submit.sh SUPERMSA <日志路径>          # 正式计分
```
