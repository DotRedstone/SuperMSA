# 历史引用对照

2026-10-31 统一规范时，所有旧分支的 HEAD 都保存为 tag `legacy/<旧分支名>`，然后删除了远端旧分支。
仍在进行的方案从 main 重建成干净分支，只保留代码、测试和说明；
旧分支里的 sweep 脚本、Slurm 作业和 runbook 由 `tools/bench/` 取代。
旧日志里出现的 T1–T5、E01–E07 等编号，可以按下表查到对应的新编号。

| 旧分支（更早的名字） | 旧 HEAD | 新编号 | 新引用 |
|---|---|---|---|
| `feat/qs-01/query-parallel-scheduler`（`feat/query-parallel-scheduler`、`release/v1-query-parallel-p6t8`） | `d0fa370` | QS-01/V03 | 已合入 main |
| `perf/dp-01/onepass`（`perf/fasta-onepass-t1`，T1/E01） | `34290cc` | DP-01/V01 | `perf/dp-01/v01-onepass` |
| `perf/dp-01/direct-map`（`perf/fasta-direct-map-e05`，E05） | `2f7e9d5` | DP-01/V02 | `perf/dp-01/v02-direct-map` |
| `perf/dp-01/config-cache`（`perf/fasta-config-cache-e06`，E06） | `f6a0caa` | DP-01/V03 | `perf/dp-01/v03-config-cache` |
| `perf/dp-01/chunk-64k`（PR #7） | `551f69a` | DP-01/V04 | `perf/dp-01/v04-chunk-64k` |
| `archive/dp-01/chunk-64k-e07`（E07） | `1060285` | DP-01/V04 的旧实现 | `legacy/archive/dp-01/chunk-64k-e07` |
| `perf/dp-01/preprocess`（`perf/fasta-preprocess`） | `665f1e7` | DP-02/V01 | `archive/dp-02/v01-rewrap` |
| `perf/dp-02/binary-sequence-db`（`perf/binary-sequence-db`） | `5c3b37d` | DP-02/V02 | `perf/dp-02/v02-bin8` |
| `perf/dp-02/huffman`（`perf/db-huffman`） | `7942aca` | DP-02/V03 | `perf/dp-02/v03-huffman` |
| `perf/dp-02/four-way`（`perf/db-four-way`） | `9dcea8b` | DP-02/V04 及 V00 对比 | `perf/dp-02/v04-dsqdata` |
| `perf/dp-03/batched-io`（`perf/bin8-batched-io-t2`，T2/E02） | `85868e2` | DP-02/V05 | `archive/dp-02/v05-bin8-batched-writer` |
| `perf/dp-04/reader-queue`（`perf/reader-queue-t3`，T3/E03） | `fa7aed6` | DP-03/V01 | `archive/dp-03/v01-queue-geometry` |
| `perf/dp-05/signal-one`（`perf/queue-signal-one-t4`，T4/E04） | `a835585` | DP-03/V02 | `perf/dp-03/v02-signal-one` |
| `perf/ck-01/ssv-band-limit`（`perf/ssv-band-limit`） | `6eef9eb` | CK-01/V01 | `archive/ck-01/v01-band-limit` |
| `probe/ev-03/jackhmmer-hotspots`（`perf/jackhmmer-hotspots`） | `c0b7300` | EV-01/V01 | `archive/ev-01/v01-hotspot` |
| `probe/ev-02/reader-worker`（`perf/reader-worker-profile-t5`，T5/P01） | `d74d874` | EV-02/V01 | `probe/ev-02/v01-reader-worker` |
| `bench/ev-01/abba-analysis`（`perf/abba-analysis-r02`） | `49570c1` | 数据已并入登记表 | `legacy/bench/ev-01/abba-analysis` |

## 集群实验目录

规范建立之前的 `experiments/supermsa/` 整体移入 `experiments/supermsa/legacy/`，保持只读。
旧编号到新编号的对应关系如下（按旧目录名）：

| 旧目录 | 新编号 |
|---|---|
| `dp/DP-01/V00-preprocess` | DP-02/V01-rewrap |
| `dp/DP-01/V01-onepass`、`V02-direct-map`、`V03-config-cache` | DP-01/V01、V02、V03（不变） |
| `dp/DP-02/V01-bin8` | DP-02/V02-bin8 |
| `dp/DP-02/V02-four-way`、`ev/EV-01/V01-four-formats` | DP-02/V00（多格式对比） |
| `dp/DP-03/V01-batched-io` | DP-02/V05-bin8-batched-writer |
| `dp/DP-04/V01-queue-geometry` | DP-03/V01-queue-geometry |
| `dp/DP-05/V01-signal-one` | DP-03/V02-signal-one |
| `ck/CK-01/V01-band-limit` | 不变 |
| `qs/QS-01/V01..V03` | 不变 |
| `ev/EV-00/V00-baseline`、`V01-msa-probe` | EV-00/V01-serial-baseline、V02-msa-probe |
| `ev/EV-02/V01-reader-worker` | 不变 |
| `ev/EV-03/V01-hotspot` | EV-01/V01-hotspot |
