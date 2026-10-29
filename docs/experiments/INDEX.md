# 实验记录规范与历史索引

## 编号与保存位置

每项任务使用稳定编号，例如 `DP-01`。方案使用稳定短标识，例如 `V02-direct-map`；标识不表示 Git 继承。每次实际运行单独建目录，建议采用 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/`。`run-id` 包含本地开始时间与 Slurm Job ID；若作业未提交，则使用明确的本地标记。原有实验目录和日志保持原样，通过索引引用，不为统一目录而搬动。

每轮重要实验保存一个 `run.json`，至少记录：任务与方案、代码提交 SHA、源码及二进制哈希、编译器与选项、数据集与 query 集合标识、Slurm Job ID 和节点、CPU/线程/内存预算、完整命令与环境变量、预处理/搜索/总墙钟时间、ROC10 与错误 query 数、原始日志及评分明细路径、结论和限制。无法取得的字段记为 `UNVERIFIED`，不得补造。

原始日志、分析报告、可重现脚本和正式评分输出分开保存。大型数据、二进制与运行日志不提交 Git；仓库仅保存小型索引、可复现脚本和适合公开的汇总。ABBA 比较记录顺序、重复次数、每轮原始时间和配对差值；一次更快不能证明方案有效。正式计时采用同一作业的 `prologue time + search time`，预处理不能提前转移。

可用 [`tools/experiments/catalog.py`](../../tools/experiments/catalog.py) 为现有工作区生成只读索引快照：

```bash
python3 tools/experiments/catalog.py --workspace "$HOME/WORK/dot" --dry-run
python3 tools/experiments/catalog.py --workspace "$HOME/WORK/dot"
```

脚本只在 `experiments/supermsa/catalog/<UTC 时间>/` 写入新快照，输出 `records.tsv`、`trials.tsv`、`aliases.tsv`、`supporting.tsv` 和 `by-task/` 分类链接视图，不移动或修改原实验。`supporting.tsv` 收录顶层源码包、脚本、分析文件和日志，不推断它们与具体运行的对应关系。历史 `t1` 至 `t5` 符号链接记入 `aliases.tsv`，不重复计算为运行。`by-task/` 中每个链接指向原目录或日志；`UNVERIFIED` 类别保留无法可靠归属的记录。探针目录的任务号仅按目录用途分类，不代表源码来源、正确性或性能结论已经核实。

`trials.tsv` 保留各类摘要的原列名；某来源不存在的列留空，`summary_path` 指向原表。重复快照名会报错。`summary.tsv` 仅有表头时记为 `HEADER_ONLY`，不算完成；未找到证据的字段记为 `UNVERIFIED`，历史记录的迁移分类保持 `UNKNOWN`。新实验的 `run.json` 可从 [`run.template.json`](../../tools/experiments/run.template.json) 开始填写，完成后须将未核实字段明确标为 `UNVERIFIED`。

## 待核对的历史来源

| 类别 | Git 来源 | 当前索引状态 |
| --- | --- | --- |
| FASTA T1/E05/E06/E07 | `perf/fasta-*` | 分支已定位；服务器原始实验与准确性待核对 |
| 四格式比较 | `perf/db-four-way`、`perf/db-huffman` | 分支已定位；原始日志待核对 |
| BIN8 T2、队列 T3/T4 | `perf/bin8-batched-io-t2`、`perf/reader-queue-t3`、`perf/queue-signal-one-t4` | 分支已定位；原始日志待核对 |
| Reader/Worker Profiling T5 | `perf/reader-worker-profile-t5` | 诊断分支已定位；原始日志待核对 |
| T1/T2/T3 ABBA r02 | `perf/abba-analysis-r02` | 分支含报告与小型 TSV；服务器原始日志待核对 |
| SSV Band Limit | `perf/ssv-band-limit` | 分支已定位；实验记录待核对 |

服务器目录调查与后续索引规则见 [服务器工作区](../architecture/SERVER_WORKSPACE.md)。
