# DP-01/V02-direct-map — 单遍解析中直接复用映射结果

- **开关**：`MSA_FASTA_DIRECT_MAP=1`，需要同时设置 `MSA_FASTA_ONEPASS=1`
- **依赖**：DP-01/V01（本分支基于 `perf/dp-01/v01-onepass`）
- **状态**：running

## 假设

V01 在校验时已经通过 `sqfp->inmap` 查出了数字码 `x`，写入时又查了一次 `abc->inmap`。
两张表只有 `*` 不同，所以对其他残基直接复用 `x`，每个残基可以少一次查表。

## 改动

`easel/esl_sqio_ascii.c` 的 `fasta_readbuf_onepass()`：`dsq = (direct_map && sym != '*') ? x : abc->inmap[sym]`。

## 正确性

`tests/test_fasta_direct_map.sh`：demo 库和一个包含 CRLF、大小写、空白、`*` 的边界样例，两种模式下数字化结果逐字节相同。
`--cpu 0/2` × `-N 1/3` 的命中表和 MSA 逐字节相同；非法字符（`-`、高位字节）都会被拒绝。

## 判定方式（在 v3 上运行之前写明）

v2 起 search 阶段通过 bin8 读取目标库，不再经过 FASTA 解析器；FASTA 读取路径只在 prologue 的 bin8 转换中执行（查询文件很小，可以忽略）。
因此本方案**只可能影响 prologue**，按 WORKFLOW 的规则，以 prologue 时间的两组配对作为判定依据，总时间仅作参考。

## 运行

ABBA 中 A = `MSA_FASTA_ONEPASS=1`，B = `MSA_FASTA_ONEPASS=1 MSA_FASTA_DIRECT_MAP=1`，衡量的是相对 V01 的增量。

| 运行 | 查询 | 节点 | job | A 总时间 | B 总时间 | 节省 | 配对 |
|---|---|---|---|---|---|---|---|
| r01-q100（基于 v2，V01+V02 一起开） | q100 | ibc11b02n35 | 16217808 | 1615.3 | 1597.5 | 17.8 s；prologue 77.0 → 68.7 | 总时间 0.0 / +35.5（inconclusive） |

## 结论

预期收益很小（远低于 1%），很可能落在 ABBA 噪声以内。优先级低于 V01 和 DP-02/V02。
