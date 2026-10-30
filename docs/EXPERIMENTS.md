# 实验登记表

规则见 [`WORKFLOW.md`](WORKFLOW.md)。状态：`proposed` → `running` → `accepted` / `rejected` / `inconclusive`；没有测量就暂缓的记为 `parked`。

**当前 main：QS-01/V03（6 进程 × 8 线程）。** 等 `EV-00/V00-main r01-q100` 复验通过后打 `v1`。

## DP — 数据通路

| 方案 | 假设 | 引用 | 依赖 | 状态 | 证据 |
|---|---|---|---|---|---|
| **DP-01** | **FASTA 文本读取** | | | | |
| V01-onepass | 把 seebuf+addbuf 合并成一次扫描 | `perf/dp-01/v01-onepass` | | running | 旧 q12 ABBA：−20.5 s（−3.5%），两组配对同号。待重跑 q100 |
| V02-direct-map | 直接复用数字映射表 | `perf/dp-01/v02-direct-map` | V01 | proposed | 预期收益远低于 1%；旧结果待从集群核对 |
| V03-config-cache | 每个文件只读取一次开关 | `archive/dp-01/v03-config-cache` | V02 | parked | 只优化实验开关本身；方案被接受后开关会删除，收益必然为零 |
| V04-chunk-64k | 读取块改为 64 KiB | `perf/dp-01/v04-chunk-64k` | | proposed | 未运行 |
| **DP-02** | **预处理数据库格式** | | | | |
| V01-rewrap | 在 prologue 中把 FASTA 改成每条记录一行 | `archive/dp-02/v01-rewrap` | | rejected | q12：552.5 → 585.4 s；prologue +34.7 s，search 无收益 |
| V02-bin8 | 预先数字化成 8-bit 库，搜索时 mmap | `perf/dp-02/v02-bin8` | | running | 旧 q12：search 约 480 s，raw 约 575 s（**不同节点**）；prologue 约 75 s。待跑 q100 同节点 ABBA |
| V03-huffman | 对数字化残基做 Huffman 编码 | `archive/dp-02/v03-huffman` | V02 | parked | 数据库常驻 page cache，I/O 不是瓶颈；解码反而增加 CPU 开销 |
| V04-dsqdata | 使用 Easel 原生 DSQDATA（5-bit） | `perf/dp-02/v04-dsqdata` | V02 | proposed | 本地 demo 验证通过；等 V02 q100 出结果后再与之对比 |
| V05-bin8-batched-writer | BIN8 转换器批量写出 | `archive/dp-02/v05-bin8-batched-writer` | V02 | inconclusive | 两组配对差值 −12.6 / +15.6 s，符号相反 |
| **DP-03** | **Reader/Worker 队列** | | | | |
| V01-queue-geometry | 块 256 条，队列 4 倍 | `archive/dp-03/v01-queue-geometry` | | rejected | q12 两次 tuned 都慢约 0.5% |
| V02-signal-one | 唤醒改为 signal-one，代替 broadcast | `perf/dp-03/v02-signal-one` | | proposed | 本地多线程测试通过；旧运行待从集群核对 |

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
| V03-p6t8 | 6 进程 × 8 线程，xargs 动态调度 | main | | accepted | 旧 q100 完整运行一次；待 v1 复验 |

## SA — 搜索算法

暂无。

## EV — 评测与诊断

| 方案 | 内容 | 引用 | 状态 | 证据 |
|---|---|---|---|---|
| **EV-00** | **基线** | | | |
| V00-main | 每个 vN 发布前的 q100 复验 | main | proposed | |
| V01-serial-baseline | 原版串行 jackhmmer | `2f85a28` | accepted | job 16155687，q100 |
| V02-msa-probe | 早期探针 | 集群 legacy | accepted | job 16158363 |
| **EV-01** | **CPU 热点** | | | |
| V01-hotspot | 单查询 perf profile（P59819_1） | `archive/ev-01/v01-hotspot` | accepted | addbuf 24.8%、seebuf 15.0%、header_fasta 11.1%（cycles:u） |
| **EV-02** | **Reader/Worker 停顿诊断** | | | |
| V01-reader-worker | 可选的分轮计时 | `archive/ev-02/v01-reader-worker` | parked | 需要时再基于 main 重建 |
