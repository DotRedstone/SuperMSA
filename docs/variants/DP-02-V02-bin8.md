# DP-02/V02-bin8 — 8-bit 预数字化数据库

- **开关**：`MSA_BIN8=1`（同时作用于 prologue 和 run_queries；默认关闭时行为与 main 完全一致）
- **依赖**：无
- **状态**：running

## 假设

EV-01 的 profile 显示，FASTA 解析（addbuf + seebuf + header_fasta）约占单查询用户态周期的 50%。
jackhmmer 每条查询要迭代 3 轮，每轮都完整解析一遍数据库，100 条查询就是 300 次。
如果在 prologue 里只用 Easel 数字化一次，搜索时直接 mmap 读取，就能省掉这 300 次文本解析。
prologue 是固定成本，search 的节省随查询数线性增长，所以 q100 的收益应该明显好于 q12。

## 改动

- `scripts/fasta_to_bin8.c`：用 Easel 自己的数字化读取器逐条转换。格式为 `MSA8DB01` + 逐条记录（5 个 u32 长度字段 + name/acc/desc + 每残基 1 字节）。
  记录顺序和所有元数据都保留，**不做任何过滤或重排**。
- `src/msa_bin8.h`：只读 mmap 的读取器，负责填充 `ESL_SQ` / `ESL_SQ_BLOCK`。多个进程通过 page cache 共享同一份数据。
- `src/jackhmmer.c`：设置了 `MSA_BIN8_DB` 时，只替换目标库的读取和 rewind；查询读取、打分、输出都不变。仅覆盖非 MPI 的串行和多线程路径。
- `prologue.sh` / `run_queries.sh`：转换在计时的 prologue 内完成；产物缺失时直接失败，不会悄悄回退到 FASTA。

## 正确性

`tests/test_bin8_smoke.sh`（由 build hook 自动执行）：在 demo 库上用 `--cpu 0/2` × `-N 1/3` 四种组合比较 raw 与 bin8，
命中表和 Stockholm MSA 都要求**逐字节相同**。

## 运行

| 运行 | 查询 | 节点 | job | A 总时间 | B 总时间 | 节省 | 配对 |
|---|---|---|---|---|---|---|---|

历史（不同节点，仅作参考）：q12 search 约 480 s，raw 约 575 s；prologue 约 75 s。

## 结论

待 q100 ABBA。
