# 历史实验目录迁移

旧实验按 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/` 迁移。迁移工具为 [`migrate_legacy.py`](../../tools/experiments/migrate_legacy.py)；每项使用同一文件系统内的重命名，旧路径保留相对符号链接。工具记录原路径、新路径、设备号、inode 和文件清单，可验证或回退。目录中的原始日志、源码快照和结果不改写。

```bash
python3 tools/experiments/migrate_legacy.py --workspace /path/to/workspace --snapshot legacy-20261030 --plan
python3 tools/experiments/migrate_legacy.py --workspace /path/to/workspace --snapshot legacy-20261030 --apply
python3 tools/experiments/migrate_legacy.py --workspace /path/to/workspace --snapshot legacy-20261030 --verify
# 仅在需要恢复旧实体路径且确认没有新作业依赖新路径时使用 --rollback。
```

| 旧位置（相对于 `experiments/supermsa/`） | 新位置 | 说明 |
| --- | --- | --- |
| `probes/fasta-preprocess-r01` | `dp/DP-01/V00-preprocess/sweep-r01` | FASTA 预处理 |
| `probes/experiments/e01-fasta-onepass/*` | `dp/DP-01/V01-onepass/*` | One-pass 三轮 |
| `probes/experiments/e05-fasta-direct-map/*` | `dp/DP-01/V02-direct-map/*` | Direct Map |
| `probes/experiments/e06-fasta-config-cache/*` | `dp/DP-01/V03-config-cache/*` | Config Cache |
| `probes/bin8-build-r01`、`probes/bin8-sweep-r01` | `dp/DP-02/V01-bin8/` | BIN8 构建与扫描 |
| `probes/four-way-build-r01` | `dp/DP-02/V02-four-way/build-r01` | 四路表示构建 |
| `probes/experiments/e02-bin8-batched-io/*` | `dp/DP-03/V01-batched-io/*` | Batched I/O 两轮 |
| `probes/experiments/e03-queue-geometry/*` | `dp/DP-04/V01-queue-geometry/*` | 队列几何两轮 |
| `probes/experiments/e04-queue-signal-one/*` | `dp/DP-05/V01-signal-one/*` | Signal One |
| `probes/ssv-band-build-r01`、`probes/ssv-band-sweep-r01` | `ck/CK-01/V01-band-limit/` | SSV Band |
| `probes/parallel-scan-20261028_230525` | `qs/QS-01/V01-parallel-scan/scan-20261028_230525` | 并行扫描 |
| `probes/candidate-repeat-r01` | `qs/QS-01/V02-candidate-repeat/repeat-r01` | 候选重复测量 |
| `runs/query-parallel-p6-t8-r01` | `qs/QS-01/V03-p6t8/query-parallel-p6-t8-r01` | Query 并行 |
| `baselines/supermsa/stdout.16155687` | `ev/EV-00/V00-baseline/job-16155687/stdout.16155687` | 基线原始日志 |
| `msa_probe.*` | `ev/EV-00/V01-msa-probe/job-16158363/` | 早期探针脚本与日志 |
| `probes/four-formats-sweep-r01` | `ev/EV-01/V01-four-formats/sweep-r01` | 四格式比较 |
| `probes/experiments/p01-reader-worker-profile/*` | `ev/EV-02/V01-reader-worker/*` | Reader/Worker 诊断 |
| `probes/perf-hotspot-r01` | `ev/EV-03/V01-hotspot/profile-r01` | 通用热点诊断 |

`probes/` 顶层散落的源码包、提交标记、历史提交脚本与分析文件分别进入 `assets/source-archives/`、`assets/source-markers/`、`assets/legacy-scripts/`、`assets/analysis/`。按现有文件名可识别归属的源码包与提交标记改用任务和方案前缀，例如 `supermsa-t1.tar` 改为 `DP-01-V01-onepass-source.tar`，原文件名保留兼容链接；文件内容对应关系仍需另行核验。`analysis/parallel-scan-r01.tsv` 同样进入 `assets/analysis/`。完整逐文件映射保存在服务器迁移清单中。历史 `t1` 至 `t5` 别名继续指向原兼容路径，旧 catalog 快照也可通过这些路径读取。

迁移只调整实验工作区，不重置服务器上的源码工作副本，不触碰比赛输入、HPL 作业、评分公式或已有 Git 分支。迁移前必须确认 SuperMSA 作业均已结束；迁移后运行 `--verify`、生成新 catalog，并检查全部旧别名和原有数据链接。正式正确性与性能结论仍以原始实验和完整运行结果为准。

## 2026-10-30 执行结果

现场确认无 SuperMSA 作业后执行了 52 项重命名；迁移前后的设备号、inode 与文件清单一致，19,445 个文件、868 个目录、187 个内部链接均保留。旧路径作为兼容链接；当前实验区全部 364 个链接可解析。推荐索引位于 `catalog/20261030T034039Z/`，包含 24 项规范运行、44 行试验、61 条别名及 42 个附属文件；旧索引视图仍可访问。

旧 `scripts/catalog.py`、`scripts/submit-run.sh` 和 `scripts/run.template.json` 在服务器上分别备份为 `scripts/catalog-2277aee.py`、`assets/legacy-scripts/submit-run-pre-migration.sh` 和 `scripts/run.template.pre-migration.json`；实体迁移后首次生成的 catalog 脚本另存为 `scripts/catalog-physical-initial.py`。当前 `scripts/submit-run.sh` 要求任务、方案和轮次参数，并支持 `--dry-run`；未实际提交新作业。只清理了本次检查生成的 4 个 Python 字节码缓存，未删除实验数据、源码包或日志。大型预处理数据库副本尚未逐项验证内容与引用，继续保留。

## 2026-10-30 后续归档与证据核对

在首轮迁移的 52 项之外，8 个历史辅助文件已归入 `assets/legacy-scripts/` 或迁移记录目录，旧位置保留相对链接。其中包括旧版 catalog、运行模板、两份已结束作业的 Slurm 脚本，以及旧别名表。逐项原路径、目标路径、inode、大小和哈希记录于服务器的 `migrations/legacy-20261030/support-cleanup.json` 与 `historical-job-scripts.json`。上文所述三个脚本备份现位于 `assets/legacy-scripts/`，旧位置仍可读；当前使用的脚本在 `scripts/`。

旧源码工作副本中忽略的 `results/` 是已完成的 100 条查询基线结果，203 个文件已在同一文件系统内移动到 `ev/EV-00/V00-baseline/job-16155687/results/`。此处不建立旧路径链接，避免新运行复用旧输出目录并覆盖历史结果。其逐文件清单、设备号、inode 和小型评分表哈希保存在 `migrations/legacy-20261030/baseline-results-move.json`；回退前须先确认旧路径仍为空且没有新作业写入。原始 stdout 和评分表未改写。

更新后的 catalog 能识别数组作业日志、不同前缀的 Slurm 日志、分层摘要及历史脚本链接。推荐快照 `catalog/20261030T113608Z/` 为 24 项运行、50 行试验、69 条别名及 50 个附属文件。三项首轮作业在 Slurm 中明确为失败，后续轮次均已完成；原始失败证据保留。服务器私有核对记录见 `migrations/legacy-20261030/REVIEW.md`。没有提交新作业或删除大型数据库；历史部分查询结果不替代正式 100 条查询验收。
