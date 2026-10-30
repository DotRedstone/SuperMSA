# 历史实验目录迁移

旧实验按 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/` 迁移。迁移工具为 [`migrate_legacy.py`](../../tools/experiments/migrate_legacy.py)；每项使用同一文件系统内的重命名，旧路径保留相对符号链接。工具记录原路径、新路径、设备号、inode 和文件清单，可验证或回退。目录中的原始日志、源码快照和结果不改写。

```bash
python3 tools/experiments/migrate_legacy.py --workspace "$HOME/WORK/dot" --snapshot legacy-20261030 --plan
python3 tools/experiments/migrate_legacy.py --workspace "$HOME/WORK/dot" --snapshot legacy-20261030 --apply
python3 tools/experiments/migrate_legacy.py --workspace "$HOME/WORK/dot" --snapshot legacy-20261030 --verify
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
