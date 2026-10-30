# 实验记录规范与历史索引

## 编号与保存位置

每项任务使用稳定编号，例如 `DP-01`。方案使用稳定短标识，例如 `V02-direct-map`；标识不表示 Git 继承。每次实际运行单独建目录，采用 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/`。新运行的 `run-id` 使用开始时间和短标识保证唯一，提交后将实际 Slurm Job ID 写入 `run.json`，不在提交前预设编号。已结束的历史实验可按[受控迁移映射](LEGACY_MIGRATION.md)重命名，并保留旧路径兼容链接和逐项回退清单；原始日志内容不改写。

每轮重要实验保存一个 `run.json`，至少记录：任务与方案、代码提交 SHA、源码及二进制哈希、编译器与选项、数据集与 query 集合标识、Slurm Job ID 和节点、CPU/线程/内存预算、完整命令与环境变量、预处理/搜索/总墙钟时间、ROC10 与错误 query 数、原始日志及评分明细路径、结论和限制。无法取得的字段记为 `UNVERIFIED`，不得补造。

原始日志、分析报告、可重现脚本和正式评分输出分开保存。大型数据、二进制与运行日志不提交 Git；仓库仅保存小型索引、可复现脚本和适合公开的汇总。ABBA 比较记录顺序、重复次数、每轮原始时间和配对差值；一次更快不能证明方案有效。正式计时采用同一作业的 `prologue time + search time`，预处理不能提前转移。

可用 [`tools/experiments/catalog.py`](../../tools/experiments/catalog.py) 为现有工作区生成只读索引快照：

```bash
python3 tools/experiments/catalog.py --workspace /path/to/workspace --dry-run
python3 tools/experiments/catalog.py --workspace /path/to/workspace
```

脚本只在 `experiments/supermsa/catalog/<UTC 时间>/` 写入新快照，输出 `records.tsv`、`trials.tsv`、`aliases.tsv`、`supporting.tsv` 和 `by-task/` 分类链接视图，不移动或修改原实验。迁移前识别原目录；迁移后识别领域/任务/方案/轮次目录，兼容链接（包括历史脚本）单列到 `aliases.tsv`，不重复计算为运行。`supporting.tsv` 收录源码包、脚本、分析文件、Slurm 日志及迁移清单，不推断它们与具体运行的对应关系。`by-task/` 中每个链接指向规范目录；任务号只用于分类，不代表源码来源、正确性或性能结论已经核实。

`trials.tsv` 保留各类摘要的原列名；某来源不存在的列留空，`summary_path` 指向原表。顶层没有摘要时，读取下一层各配置目录中的 `summary.tsv`，每行保留自身来源。重复快照名会报错。`summary.tsv` 仅有表头时记为 `HEADER_ONLY`，不算完成；未找到证据的字段记为 `UNVERIFIED`，历史记录的迁移分类保持 `UNKNOWN`。新实验的 `run.json` 可从 [`run.template.json`](../../tools/experiments/run.template.json) 开始填写，完成后须将未核实字段明确标为 `UNVERIFIED`。

新实验可用 [`submit_run.sh`](../../tools/experiments/submit_run.sh) 在规范目录下建立运行并提交基线作业；服务器工作区的副本位于 `experiments/supermsa/scripts/submit-run.sh`。先运行 `--dry-run` 检查路径，正式提交后核对 `run.json` 中的 Job ID、日志和评分字段。该脚本只记录初始元数据，不代替完整实验验收。

## 当前历史索引

服务器当前推荐快照为 `experiments/supermsa/catalog/20261030T113608Z/`。规范实体路径覆盖 `DP-01` 至 `DP-05`、`CK-01`、`QS-01`、`EV-00` 至 `EV-03`；逐项新旧路径见[迁移映射](LEGACY_MIGRATION.md)。24 项运行中有 10 项带试验行、3 项摘要仅有表头、11 项没有 `summary.tsv`；合计摘录 50 行，另有 69 条兼容路径及 50 个附属文件。新增的 6 行来自已完成的 `QS-01` 数组作业各配置目录；三项 `HEADER_ONLY` 对应失败的首轮作业，后续轮次已完成。摘要状态本身仍不表示 Slurm 作业状态。源码提交、日志、评分与正式正确性须按各项原始证据判读，不能由目录名或摘要行数推断。

历史 `EV-00` 基线和 `QS-01/V03` 各有一轮 100 条查询的完成日志与评分明细；前者的 203 个结果文件已归入规范基线运行目录。其他候选仅有部分查询摘要，不能据此宣称正式通过。`DP-01/V04` 的 Git 分支已收录在[优化索引](../optimization/INDEX.md)，本次服务器旧实验中没有对应的实体运行目录。若要合入该候选，须补跑同数据、同资源的基线与候选配对测量，以及 100 条查询的正确性检查；历史失败首轮无需为了整理目录重跑。服务器工作区边界见[工作区说明](../architecture/SERVER_WORKSPACE.md)。
