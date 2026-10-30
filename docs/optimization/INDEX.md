# 优化任务索引

任务号是长期引用标识，不表示实现顺序或 Git 继承。代码分支采用对应的小写任务号，逐项新旧名称见[分支迁移记录](../architecture/MIGRATION.md)；性能和正式正确性状态需以原始实验记录复核。

| 任务 | 范围 | 当前分支或来源 | 集成状态 |
| --- | --- | --- | --- |
| `DP-01` | FASTA Reader | `perf/dp-01/` 下的 preprocess、onepass、direct-map、config-cache、chunk-64k；旧 E07 存档 | 候选，未入 `main` |
| `DP-02` | 数据表示与预处理 | `perf/dp-02/` 下的 binary-sequence-db、huffman、four-way | 候选，未入 `main` |
| `DP-03` | BIN8 Batched I/O | `perf/dp-03/batched-io` | 候选，未入 `main` |
| `DP-04` | Reader/Worker 队列与 Block Geometry | `perf/dp-04/reader-queue` | 候选，未入 `main` |
| `DP-05` | 队列唤醒策略 | `perf/dp-05/signal-one` | 候选，未入 `main` |
| `CK-01` | SSV SIMD Band Limit | `perf/ck-01/ssv-band-limit` | 候选，未入 `main` |
| `QS-01` | Query 级并行 | `feat/qs-01/query-parallel-scheduler`、P6T8 | 候选，未入 `main` |
| `SA-01` | 搜索策略与质量权衡 | 暂无已确认方案 | 未开始 |
| `EV-00` | 基线与早期探针 | 服务器旧基线日志、MSA 探针 | 历史记录；无新的性能结论 |
| `EV-01` | 四格式与 ABBA 比较 | `perf/dp-02/four-way`、`bench/ev-01/abba-analysis` | 历史实验待复核 |
| `EV-02` | Reader/Worker 诊断 | `probe/ev-02/reader-worker` | 诊断分支，未入 `main` |
| `EV-03` | 通用热点诊断 | `probe/ev-03/jackhmmer-hotspots` | 历史诊断；未入 `main` |
| `EV-04` | 实验索引与证据完整性 | `fix/ev-04/catalog-evidence` | 维护工具修复；不改变算法 |

`DP-01` 的方案标识为 `V01-onepass`、`V02-direct-map`、`V03-config-cache`、`V04-chunk-64k`。旧 E06 与 E07 都从 E05 演进，E07 **不**继承 E06；当前 V04 候选是从 `main` 单独实现的[草稿 PR #7](https://github.com/DotRedstone/SuperMSA/pull/7)。历史 T/E 编号仍作为原始记录别名，不改写旧日志。

具体分支与提交快照见 [迁移索引](../architecture/MIGRATION.md)。
