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
| 发布 | tag `vN`：main 每接受一个方案，就递增一次 | `v1` |
| 归档 | tag `archive/<task>/<variant>` | `archive/dp-02/v01-rewrap` |

- 方案分支**从 main 开**。如果确实依赖另一个未合并的方案，就从那个方案的分支开，并在登记表的"依赖"列写明。依赖的方案被拒绝时，本方案也要重新评估。
- 结束时：accepted → `git merge --no-ff` 进 main，打 `vN`，删除分支；rejected / inconclusive / parked → 打 `archive/...` tag，删除分支。
  `parked` 表示没有测量就暂缓（写明理由），以后可以从 archive tag 恢复。
  远端只保留 main 和**进行中**的方案分支。
- commit：`<type>(<scope>): <描述>`。type ∈ `feat perf fix test docs build refactor chore`，scope 优先写领域（`dp ck qs sa ev`）。描述用中文或英文都可以。

## 3. 方案分支里放什么

- 代码改动 + 测试 + 一页说明 `docs/variants/<TASK>-<VNN>-<slug>.md`，包括：假设、改动、开关、正确性依据、运行结果、结论。
- 新行为一律用开关控制，**默认关闭**：环境变量 `MSA_<NAME>=1`。这样同一个 build 就能跑 ABBA 的两个臂。
- 如果需要额外编译工具（例如预处理转换器），写在 `tools/bench/build_hook.sh` 里，`build.sh` 会自动执行它。
- **不放**专用的 sweep 脚本、Slurm 作业、runbook、手抄的日志。测评一律用 `tools/bench/`。

## 4. 评测标准

1. **正确性门槛**（不满足就不看时间）：每个 trial 的 `score.py` 全部 correct（ROC10 ≥ 基线的 90%），
   并且命中表与第 1 个 trial 等价（`compare_hit_tables.py`：目标集合必须完全一致，分数和 E 值只允许打印精度级别的漂移）。
2. **对照**：同一个独占节点，ABBA 顺序，同一个 build，只用开关切换。总时间 = prologue + search。
3. **筛选**用 `q12`，**接受**必须用 `q100`。带预处理的方案，prologue 成本是固定的，在 q12 上会被系统性低估，**不能只凭 q12 否决**。
4. **判定**：两组配对差值同号才能判 faster / slower，否则判 inconclusive。

## 5. 集群

```
~/WORK/dot/
  preliminary/                         比赛数据，只读
  SuperMSA/                            仓库，只通过 git pull --ff-only 更新，不在这里改代码，也不在这里编译
  experiments/supermsa/
    builds/<sha12>/                    按 commit 编译的产物，只读；BINARIES.sha256 存在即表示编译完整
    <dp|ck|qs|sa|ev>/<TASK>/<VARIANT>/<RUN>/
        run.env  run.json  queries.txt  summary.tsv  report.txt  slurm-<job>.out  trials/
    legacy/                            规范建立之前的所有实验，只读
```

运行目录**只写一次**：失败了就开新的 rNN，绝不在原目录里重跑。

### 一次实验的完整流程

集群能访问 GitHub，所以同步就是：本地 push，集群 pull。集群上的 git 是 1.8.3，脚本里没有使用新版本的语法。
`build.sh` 和 `new_run.sh` 收到分支名时，会自动解析成 `origin/<分支名>`。

```bash
# 本地
git push origin main perf/dp-02/v02-bin8

# 登录节点：更新仓库（只允许快进，集群上永远不改代码）
cd ~/WORK/dot/SuperMSA && git pull --ff-only

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
