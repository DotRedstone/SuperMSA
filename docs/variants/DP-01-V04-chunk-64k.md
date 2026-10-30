# DP-01/V04-chunk-64k — FASTA 读取块从 4 KiB 增大到 64 KiB

- **开关**：`MSA_FASTA_CHUNK_64K=1`（只作用于普通的可寻址 FASTA 文件；stdin、gzip 和内存解析都不受影响）
- **依赖**：无
- **状态**：proposed

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

## 结论

待 q12 筛选。
