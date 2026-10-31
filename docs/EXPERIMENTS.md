# 实验登记表

规则见 [`WORKFLOW.md`](WORKFLOW.md)。状态：`proposed` → `running` → `accepted` / `rejected` / `inconclusive`；没有测量就暂缓的记为 `parked`。

**当前 main：v3 = v2.1 + DP-01/V04（64K 读取块）。** v1 = QS-01/V03（6 进程 × 8 线程）。

| 版本 | 内容 | q100 总时间 | 证据 |
|---|---|---|---|
| v1 | QS-01/V03 | 3576.1 s | EV-00/V00-main r01-q100，job 16208885 |
| v2 | v1 + DP-02/V02 | 约 1600 s（−53.8%） | DP-02/V02-bin8 r01-q100，job 16208886 |
| **v2.1** | v2 + `PARALLEL` 默认改为 6 | **1675.4 s**（prologue 79.8 + search 1595.6） | 正式入口 `job_baseline.slurm` 不加任何参数，job 16217895，0/100 incorrect，mean ROC10 0.7231；已提交榜单。v2.1 之前的正式入口实际是串行 |
| v3 | v2.1 + DP-01/V04（64K 读取块，默认开启） | 待 `--official` 复验 | DP-01/V04 r02-q100：−16.7 s，主要来自 prologue |

**教训**：q12 只有 12 条查询，6 个槽位只能跑两轮，墙钟由最慢的 Q969Q1_1（约 350 s，几乎纯计算，bin8 只快了 6 s）决定，
所以 q12 的墙钟会严重低估大多数查询上的收益（bin8：q12 search −14%，q100 −56%）。
q100 中各查询的单条耗时：中位数 202 → 79 s（×0.39），q12 成员与其余查询的中位数相同，**并不是 q12 的查询更重**。
DP 类方案一律直接用 q100；报告里的 `query_sum`（各查询耗时之和）不受拖尾影响，可以作为辅助参考。

**下一步**：v2 之后 search 约占总时间的 95%，prologue 已经不到 5%。按收益上限排序：
1. **EV-01 重新做 profile**（在 v3 上）：找出 search 阶段的新热点，决定 CK 方向从哪里下手。
2. **QS-02 长查询优先调度**：理想墙钟与实际墙钟差约 75 s。
3. **DP-02/V06 多线程 bin8 转换**：prologue 剩约 65 s。
4. DP-01/V01+V02 在 v3 上按 prologue 规则重测（上限约 10 s）。

## DP — 数据通路

| 方案 | 假设 | 引用 | 依赖 | 状态 | 证据 |
|---|---|---|---|---|---|
| **DP-01** | **FASTA 文本读取** | | | | |
| V01-onepass | 把 seebuf+addbuf 合并成一次扫描 | `perf/dp-01/v01-onepass` | | running | 旧 q12 ABBA：−20.5 s（−3.5%），两组配对同号。待重跑 q100 |
| V02-direct-map | 直接复用数字映射表 | `perf/dp-01/v02-direct-map` | V01 | running | V01+V02 r01-q100（基于 v2）：总时间配对 0.0 / +35.5 → inconclusive；prologue 77.0 → 68.7 s。按 prologue 规则在 v3 上重测 |
| V03-config-cache | 每个文件只读取一次开关 | `archive/dp-01/v03-config-cache` | V02 | parked | 旧 q12：−5.8 s，但这部分收益来自每条记录调用 getenv 的开销；方案被接受后开关会删除，这部分开销自然消失 |
| V04-chunk-64k | 读取块改为 64 KiB | main（v3） | | accepted | r02-q100（基于 v2）：1607.0 → 1590.3 s，配对 +9.7 / +23.7；prologue 74.8 → 65.5 s |
| **DP-02** | **预处理数据库格式** | | | | |
| V01-rewrap | 在 prologue 中把 FASTA 改成每条记录一行 | `archive/dp-02/v01-rewrap` | | rejected | q12：552.5 → 585.4 s；prologue +34.7 s，search 无收益 |
| V02-bin8 | 预先数字化成 8-bit 库，搜索时 mmap | main（v2） | | accepted | r01-q100 ABBA：3464.5 → 1600.7 s（−53.8%），配对 +1879 / +1848，全部正确且与 v1 等价 |
| V03-huffman | 对数字化残基做 Huffman 编码 | `archive/dp-02/v03-huffman` | V02 | rejected | 旧四格式对比：search 828 s（比 raw 慢 47%），prologue 264 s |
| V04-dsqdata | 使用 Easel 原生 DSQDATA（5-bit） | `archive/dp-02/v04-dsqdata` | V02 | rejected | 旧四格式对比：search 484.5 s，与 bin8 持平；prologue 123 s，比 bin8 多 46 s。任何查询规模下都不如 V02 |
| V05-bin8-batched-writer | BIN8 转换器批量写出 | `archive/dp-02/v05-bin8-batched-writer` | V02 | inconclusive | 两组配对差值 −12.6 / +15.6 s，符号相反 |
| **DP-03** | **Reader/Worker 队列** | | | | |
| V01-queue-geometry | 块 256 条，队列 4 倍 | `archive/dp-03/v01-queue-geometry` | | rejected | q12 两次 tuned 都慢约 0.5% |
| V02-signal-one | 唤醒改为 signal-one，代替 broadcast | `archive/dp-03/v02-signal-one` | | rejected | 旧 q12 ABBA：两组配对 −0.9 / −2.4 s，略慢 |

## CK — 计算核心

| 方案 | 假设 | 引用 | 依赖 | 状态 | 证据 |
|---|---|---|---|---|---|
| **CK-01** | **SSV 过滤器** | | | | |
| V01-band-limit | 限制有效 band 宽度（8/10/12/14） | `archive/ck-01/v01-band-limit` | | rejected | q12 sweep 无稳定收益 |

## QS — 查询调度

| 方案 | 假设 | 引用 | 依赖 | 状态 | 证据 |
|---|---|---|---|---|---|
| **QS-01** | **查询级并行** | | | | |
| V01-parallel-scan | 扫描进程数 × 线程数组合 | 集群 legacy | | accepted | 选出 6×8 |
| V02-candidate-repeat | 候选组合重复测量 | 集群 legacy | | accepted | |
| V03-p6t8 | 6 进程 × 8 线程，xargs 动态调度 | main | | accepted | v1 复验 3576.1 s |
| V04-p7t8 | 7 进程 × 8 线程，用满 56 核（6×8 是在 bin8 之前、读取仍是瓶颈时选的） | main，只用环境变量 `PARALLEL=7` | | proposed | |
| **QS-02** | **查询启动顺序** | | | | |
| V01-longest-first | 按查询长度从长到短启动 | `feat/qs-02/v01-longest-first` | | proposed | 模拟：1524 → 1491 s |

## SA — 搜索算法

暂无。

## EV — 评测与诊断

| 方案 | 内容 | 引用 | 状态 | 证据 |
|---|---|---|---|---|
| **EV-00** | **基线** | | | |
| V00-main | 每个 vN 的 q100 复验 | main | accepted | v1：r01-q100，3576.1 s，100/100，与历史 QS-01 等价；v2.1：r02-official（正式入口），1675.4 s，0/100 incorrect |
| V01-serial-baseline | 原版串行 jackhmmer | `2f85a28` | accepted | job 16155687，q100 |
| V02-msa-probe | 早期探针 | 集群 legacy | accepted | job 16158363 |
| **EV-01** | **CPU 热点** | | | |
| V01-hotspot | 单查询 perf profile（P59819_1） | `archive/ev-01/v01-hotspot` | accepted | addbuf 24.8%、seebuf 15.0%、header_fasta 11.1%（cycles:u） |
| V02-v3-hotspot | v3（bin8 + 64K）上的单查询 profile：最慢、次慢、中位数、最快各一条 | main | proposed | Q969Q1_1、P41772_1、P20429_1、P75884_1 |
| **EV-02** | **Reader/Worker 停顿诊断** | | | |
| V01-reader-worker | 可选的分轮计时 | `archive/ev-02/v01-reader-worker` | parked | 需要时再基于 main 重建 |
