# 仓库约定（给人和 agent）

开始工作前读 [`docs/WORKFLOW.md`](docs/WORKFLOW.md) 和 [`docs/EXPERIMENTS.md`](docs/EXPERIMENTS.md)，并执行一次 `git status --short`。

- 编号、分支、commit、评测标准、集群目录，全部以 `docs/WORKFLOW.md` 为准。
- 比赛入口 `prologue.sh`、`run_queries.sh`、`job_baseline.slurm`、`score.py` 的调用方式不能改变。
- 不得依据序列 ID 或 header 内容（SCOP 标注、`annotated_` 前缀等）筛选、排序或剔除数据库序列。预处理必须在计时的 `prologue.sh` 内完成。
- 改了 Bash 要跑 `bash -n`，改了 Python 要跑 `python3 -m py_compile`。改了行为要跑 `tests/` 中相关的测试（不需要 Slurm，也不读比赛数据）。
- 测试通过、编译成功，都不等于验收。验收只认 `tools/bench` 跑出的 q100 ABBA。
- 集群：登录节点只做 git、mkdir、sbatch；编译在 test01–04；运行走 Slurm。home 在计算节点上只读，所有东西放在 `~/WORK`。
