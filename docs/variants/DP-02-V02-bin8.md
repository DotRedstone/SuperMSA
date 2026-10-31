# DP-02/V02-bin8 — 8-bit 预数字化数据库

- **开关**：`MSA_BIN8`，被接受后**默认开启**；设 `MSA_BIN8=0` 可回到原始 FASTA 路径（仅用于实验对照）
- **依赖**：无
- **状态**：accepted（v2）

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
| r01-q100 | q100 | ibc11b10n08 | 16208886 | 3464.5 | 1600.7（prologue 74.7 + search 1526.0） | 1863.8 s（53.8%） | +1879.3 / +1848.3 |

历史（同节点四格式对比，q12）：search 561.3 → 481.5 s。q12 的收益远小于 q100，因为 q12 里多是计算密集的查询。

## 结论

accepted：4 个 trial 全部 100/100 正确，并且与历史 QS-01 的 q100 命中表等价。合入 main 后默认开启，转换器由顶层 `make` 编译。
