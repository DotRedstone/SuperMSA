# DP-01/V04-chunk-64k — FASTA 读取块从 4 KiB 增大到 64 KiB

- **开关**：`MSA_FASTA_CHUNK_64K`，v3 起**默认开启**，设为 `0` 可恢复 4 KiB 读取（只作用于普通的可寻址 FASTA 文件；stdin、gzip 和内存解析都不受影响）
- **依赖**：无
- **状态**：accepted（v3）

## 假设

Easel 默认每次 `fread` 4 KiB（`eslREADBUFSIZE`）。数据库有几 GB，每次扫描要调用上百万次 `loadmem`，还要反复跨越块边界。
改成 64 KiB 后，调用次数和边界处理都减少到 1/16。

## 改动

`easel/esl_sqio_ascii.[ch]`：新增 `fasta_read_chunk` 字段，在打开文件时根据开关取值；`loadmem()` 改用这个字段。
格式自动识别可能已经缓冲了 4 KiB 前缀，这种情况下会把缓冲区扩大到 64 KiB。

## 正确性

`tests/test_fasta_read_chunk.{c,sh}`：在 demo 库和跨 4K/64K 边界的长 header、长序列、CRLF、无结尾换行等样例上，
逐条比较记录内容、重绕行为和非法输入的拒绝结果；同时比较 `--cpu 0/2` × `-N 1/3` 下 jackhmmer 的命中表和 MSA，要求逐字节相同。

## 运行

| 运行 | 查询 | 节点 | job | A 总时间 | B 总时间 | 节省 | 配对 |
|---|---|---|---|---|---|---|---|
| r01-q12（基于 v1） | q12 | ibc11b02n02 | 16208887 | 559.9 | 484.6 | 75.3 s（13.5%）；query_sum −21% | +76.6 / +73.8 |
| r02-q100（基于 v2） | q100 | ibc11b02n03 | 16217807 | 1607.0 | 1590.3 | 16.7 s（1.0%）；prologue 74.8 → 65.5 | +9.7 / +23.7 |

## 结论

accepted（v3）。在 v2 上，search 已经不读 FASTA，收益只来自 prologue 里的 bin8 转换：约 −9 s，四个 trial 的 prologue 两两配对都是一致的。
