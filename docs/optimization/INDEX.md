# 优化任务索引

任务号是长期引用标识，不表示实现顺序或 Git 继承。以下映射依据 2026-10-30 的远端分支名称与提交关系整理；性能和正式正确性状态需以原始实验记录复核。

| 任务 | 范围 | 已有分支或历史名称 | 集成状态 |
| --- | --- | --- | --- |
| `DP-01` | FASTA Reader | One-pass（T1）、Direct Map（E05）、Config Cache（E06）、64 KiB 读取（E07） | 候选，未入 `main` |
| `DP-02` | 数据表示与预处理 | BIN8、DSQDATA、Huffman、Four-way | 候选，未入 `main` |
| `DP-03` | BIN8 Batched I/O | T2 | 候选，未入 `main` |
| `DP-04` | Reader/Worker 队列与 Block Geometry | T3 | 候选，未入 `main` |
| `DP-05` | 队列唤醒策略 | Signal One（T4） | 候选，未入 `main` |
| `CK-01` | SSV SIMD Band Limit | `perf/ssv-band-limit` | 候选，未入 `main` |
| `QS-01` | Query 级并行 | P6T8 | 功能分支与 release 分支同 HEAD，未入 `main` |
| `SA-01` | 搜索策略与质量权衡 | 暂无已确认方案 | 未开始 |
| `EV-00` | 基线与早期探针 | 服务器旧基线日志、MSA 探针 | 历史记录；无新的性能结论 |
| `EV-01` | 四格式与 ABBA 比较 | Four-way、ABBA r02 | 历史实验待索引 |
| `EV-02` | Reader/Worker 诊断 | T5 | 诊断分支，未入 `main` |
| `EV-03` | 通用热点诊断 | Perf Hotspot r01 | 历史诊断；未入 `main` |

`DP-01` 的新方案标识建议为 `V01-onepass`、`V02-direct-map`、`V03-config-cache`、`V04-chunk-64k`。它们只是索引；其中 E06 与 E07 都从 E05 演进，E07 **不**继承 E06。历史 T/E 编号仍作为原始记录别名，不改写旧日志。

具体分支与提交快照见 [迁移索引](../architecture/MIGRATION.md)。
