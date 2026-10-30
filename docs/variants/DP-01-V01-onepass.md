# DP-01/V01-onepass — FASTA 单遍数字化解析

- **开关**：`MSA_FASTA_ONEPASS=1`（未设置时完全走原来的 seebuf + addbuf 两遍流程）
- **依赖**：无
- **状态**：running

## 假设

EV-01 显示 `addbuf` 占 24.8%、`seebuf` 占 15.0%。这两个函数对同一块缓冲区各扫描一遍：一遍校验，一遍映射。
合并成一遍，可以减少内存访问和分支开销。

## 改动

只改 `easel/esl_sqio_ascii.c`：新增 `fasta_readbuf_onepass()`，在一次扫描里同时完成校验、ASCII 到数字的映射、残基计数和行/偏移记录。
只作用于普通 FASTA 的数字化 `sqascii_Read()`（多线程的 `ReadBlock` 也经过它）。其他格式以及 ReadInfo/ReadWindow 路径都不变。
错误处理、EOF、CRLF、空白、行号和记录偏移都必须与原解析器一致。

## 正确性

`tests/test_fasta_onepass.sh`（由 build hook 执行）：
- demo 库和一个带空白/特殊残基的小样例，经两条路径数字化后逐字节相同（`tests/fasta_dump`）。
- `--cpu 0/2` × `-N 1/3` 四种组合下，命中表和 MSA 逐字节相同。
- 非法字符在两条路径下都会被拒绝。

## 运行

| 运行 | 查询 | 节点 | job | A 总时间 | B 总时间 | 节省 | 配对 |
|---|---|---|---|---|---|---|---|
| legacy t1-abba-r02 | q12 | ibc11b04n19 | 16170657 | 581.5 | 561.05 | 20.45 s（3.5%） | +18.4 / +22.5 |

## 结论

q12 两组配对同号，有希望。待 q100 ABBA。
