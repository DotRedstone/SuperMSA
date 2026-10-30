# DP-02/V04-dsqdata — Easel 原生 DSQDATA（5-bit 打包）目标库

- **开关**：`MSA_DSQDATA=1`（与 `MSA_BIN8` 互斥）；可选 `MSA_DSQ_UNPACKERS=<n>`，设置解包线程数
- **依赖**：DP-02/V02（本分支基于 `perf/dp-02/v02-bin8`，复用 `msa_bin8.h` 中的元数据拷贝函数和 jackhmmer 接入点）
- **状态**：proposed

## 假设

与 V02 一样，都是只在 prologue 里数字化一次。区别在于 DSQDATA 是上游维护的格式：5-bit 打包后文件约为 BIN8 的 5/8，
并且自带异步读取和多线程解包流水线。问题是：解包成本能否被更小的内存带宽占用抵消？

## 改动

- `scripts/fasta_to_dsqdata.c` 调用 `esl_dsqdata_Write()`；`scripts/verify_dsqdata.c` 逐条对比往返结果。
- `easel/esl_dsqdata.[ch]`：新增 `esl_dsqdata_OpenWithUnpackers()`，可以控制解包线程数；原有的 `Open` 行为不变。
- `src/msa_dsq_bridge.h`：把 DSQDATA chunk 转成 `ESL_SQ_BLOCK`。迭代之间采用 lazy reopen，避免最后一次 rewind 时因未消费的预取而死锁。
- `src/jackhmmer.c`：设置了 `MSA_DSQDATA_DB` 时替换目标库读取；`prologue.sh` / `run_queries.sh` 负责计时转换和产物检查。

## 正确性

`tests/test_dsqdata_smoke.sh`：在 demo 库上验证往返无损，`--cpu 0/2` × `-N 1/3` 下命中表和 MSA 与 raw 逐字节相同，每次运行限时 120 秒。

## 运行

先等 V02 的 q100 结果出来，再决定是否跑 V02 vs V04（A=`MSA_BIN8=1`，B=`MSA_DSQDATA=1`）。

| 运行 | 查询 | 节点 | job | A 总时间 | B 总时间 | 节省 | 配对 |
|---|---|---|---|---|---|---|---|

## 结论

待测。
