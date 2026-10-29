# 旧分支与新索引

本页记录 2026-10-30 从公开远端获取的分支快照。HEAD 只表示当时的引用位置，不证明构建、正确性、性能或正式提交有效。旧分支保持原名和原提交；新任务号是文档与实验索引，不要求重命名旧分支。

| 远端分支 | HEAD | 归属与处理方式 |
| --- | --- | --- |
| `main` | `2f85a28` | 稳定基线；先集成工程规范文档 |
| `feat/query-parallel-scheduler` | `d0fa370` | `QS-01`，候选功能 |
| `release/v1-query-parallel-p6t8` | `d0fa370` | 与上一分支同 HEAD；保留历史引用，正式发布改用验收后的 tag |
| `perf/jackhmmer-hotspots` | `c0b7300` | `EV`，瓶颈分析来源 |
| `perf/fasta-preprocess` | `665f1e7` | `DP-02`，预处理实验来源 |
| `perf/binary-sequence-db` | `5c3b37d` | `DP-02`，二进制数据库实验来源 |
| `perf/db-huffman` | `7942aca` | `DP-02`，Huffman 实验来源 |
| `perf/db-four-way` | `9dcea8b` | `DP-02`/`EV-01`，多条后续分支的历史基础；不直接整体合并 |
| `perf/bin8-batched-io-t2` | `85868e2` | `DP-03`，保留 T2 别名 |
| `perf/reader-queue-t3` | `fa7aed6` | `DP-04`，保留 T3 别名 |
| `perf/queue-signal-one-t4` | `a835585` | `DP-05`，保留 T4 别名 |
| `perf/reader-worker-profile-t5` | `d74d874` | `EV-02`，诊断分支，保留 T5 别名 |
| `perf/abba-analysis-r02` | `49570c1` | `EV-01`，历史报告与 TSV；原始日志待核对 |
| `perf/fasta-onepass-t1` | `34290cc` | `DP-01/V01-onepass`，保留 T1 别名 |
| `perf/fasta-direct-map-e05` | `2f7e9d5` | `DP-01/V02-direct-map`，保留 E05 别名 |
| `perf/fasta-config-cache-e06` | `f6a0caa` | `DP-01/V03-config-cache`，保留 E06 别名 |
| `perf/fasta-chunk-64k-e07` | `82913e7` | `DP-01/V04-chunk-64k`，保留 E07 别名 |
| `perf/ssv-band-limit` | `6eef9eb` | `CK-01`，候选性能方案 |

## 已核实的继承关系

`main` 是这些旧分支的祖先。`feat/query-parallel-scheduler` 是 `perf/db-four-way` 等性能分支的祖先。`perf/db-four-way` 是 T1、T2、T3、T4、T5 与 ABBA r02 分支的祖先。FASTA 链为 T1 → E05 → E06；E07 也继承 E05，但不继承 E06。关系由本地 `git merge-base --is-ancestor` 核对，不能把名称当成继承证明。

## 后续集成

1. 保留全部旧引用及其实验报告。新文档和目录规范先独立落地。
2. 对每个候选方案记录代码来源、父提交、必要差异和正确性证据；必要时从旧分支提取最小改动。
3. 完成集群验证后，决定是否集成到 `main`。不以旧分支最新 HEAD 或报告中的单次结果直接作稳定性结论。
4. 服务器原始日志、二进制、工作目录和作业关系核对后，再填写文件位置迁移表。未核实的路径标为 `UNVERIFIED`；不批量移动历史文件。

本次工程规范变更不删除、改名、rebase 或 force-push 上述分支，也不创建没有实际联合验证任务的领域集成分支。
