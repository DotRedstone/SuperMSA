# Huffman（哈夫曼）编码数据库实验

**状态：源码已提交，尚未在 test01 编译/验证，尚未运行完整比赛数据库。**
本分支是 `perf/binary-sequence-db` 的后续独立实验；
**不会改变当前已提交 Slurm 的 `bin8-sweep-r01` 快照**，也不会更改 v1 成绩。

## 实验目标

三个可比较的输入路径：

- `raw`：原始 FASTA，Easel 原本的文本解析和数字化
- `bin8`：prologue 用 Easel 一次数字化，每残基 8 bit；搜索直接 mmap 读取
- `huff`：prologue 先从原始 FASTA 数字化，再统计完整数据库的残基频率，生成规范 Huffman 码并编码全部残基；搜索从 mmap 数据按记录解压为 Easel `ESL_DSQ`

Huffman ≠ Hash。哈希不可逆，不能拿来替代精确的生物序列；Huffman 是无损变长编码。

## 安全与计时约束

原始数据库 `preliminary/database.fasta` 必须在计时的 `prologue.sh` 中处理；
**不允许提前在 test01 对比赛数据库生成压缩结果**。
Huffman 的 BIN8 中间文件也在 prologue 计时区内生成，用完删除。
所有目标序列、原始次序、name、accession、description、taxid 和数字化残基均必须保持一致。
不能通过 header、ID、SCOP 标注、`annotated_` 等过滤/排序任何序列。

Huffman 的文件格式为 `MSAHUF01` + 256 个 Huffman 码长字节 +
逐条记录的元数据与压缩 bitstream。码树只取决于残基值和全数据库频率，
不依据 Query 或结果标签进行选择。每条记录单独 byte-align，可按块读取，
无需解码整个文件后再搜索。

## 构建与测试

需要 gcc、make、autoconf、bash。**务必将本分支解压到全新的
`huffman-build-r01/source` 目录，不要覆盖正在运行的 BIN8 实验。**

在 test01：

```bash
module load compilers/gcc/v12.2.0
cd ~/WORK/dot/experiments/supermsa/probes/huffman-build-r01/source
bash scripts/build_huffman_candidate.sh
```

脚本首先重新构建 JackHMMER/原有 BIN8，再编译 Huffman 编码器
`scripts/bin8_to_huffman`、逐字节验证器
`scripts/verify_huffman`，随后测试：

1. 对仓库自带的 15,177 条 toy FASTA 全部编码并 **逐条逐字节对比**；
2. 人为破坏文件头和 Huffman 码长，验证解码入口拒绝；
3. `--cpu 0`、`--cpu 2` 各自测试 `-N 1`、`-N 3`；
4. 三种方式的非注释命中表及 Stockholm MSA 完全一致。

成功标志：
`HUFFMAN_EXACT_ROUNDTRIP=PASS`、
`HUFFMAN_TOY_CORRECTNESS=PASS`、
`HUFFMAN_BUILD_AND_SMOKE=PASS`。

失败先看 `huffman.converter-build.log`、
`huffman.verifier-build.log`、`huffman.smoke.log` 和
`bin8.make.log`，**不准直接跑性能测试**。

## Slurm 对照

仅在 toy 测试全部通过后，复制构建快照到全新的
`.../probes/huffman-sweep-r01/source`，把
`job_huffman_sweep.slurm` 复制到运行目录的 `job.slurm`。

从 `huffman-sweep-r01` 目录提交：

```bash
sbatch job.slurm
```

默认要求这两个历史输入存在：
`.../probes/parallel-scan-20261028_230525/queries.txt`（12 条）；
`.../runs/query-parallel-p6-t8-r01/results/tbl`（v1 命中表）。
如路径不同，在 **sbatch 时** 设置 `BENCH_QUERY_LIST` 或
`BENCH_BASELINE_TBL` 环境变量覆盖，不要修改历史实验产物。

测试顺序：`raw, bin8, huff, huff, bin8, raw`；
一节点独占、每次 12 Query、6×8、最多 3 轮迭代，
每次转换均在计时的 prologue 进行，且输出目录不复用。
`summary.tsv` 给出 `prologue_s`、`search_s`、`total_s`
及压缩文件大小。比较 **总耗时**，不是仅比较压缩率。
预热不包含在当前 `search_s` 计时中，三个模式采用相同规则。

## 后续

本分支不是 5-bit 方案。5-bit 需要另开独立分支接入
Easel `esl_dsqdata` 读取路径，再做相同的无损性检查和三格式/四格式比较。
Huffman 在 CPU/Cache 路径上有额外按位分支解码开销，
**不保证更快**；如果压缩收益不能覆盖解码和预处理，应保留 BIN8 或 RAW。
12 Query 只作筛选；最终要用 100 Query 验证准确率和端到端时间。
