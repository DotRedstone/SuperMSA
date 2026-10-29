# JackHMMER CPU 热点剖析（第一轮）

目标：在不修改已有 100 Query 成绩的前提下，用一个独立 Slurm 作业采样单条 Query 的用户态 CPU 热点，再决定是否深入 HMMER SSE、Pipeline 或 DB 读取代码。

## 已验证的性能背景
- 原始 baseline：21411.2 s，100 Query，ROC10=0.7231。
- Query-level parallel v1：3518.5 s，PARALLEL=6，CPU=8，100/100，incorrect=0/100。
- 上述性能成绩来自实际超算日志；不是本分支重新运行得到的结果。

## 目录和资源约束
- 源码在 `~/WORK/dot/SuperMSA`。
- 已提交版本的原始快照在 `~/WORK/dot/experiments/supermsa/runs/query-parallel-p6-t8-r01/source`，不要修改。
- 新实验统一存入 `~/WORK/dot/experiments/supermsa/probes/`。
- 不在登录节点跑性能剖析。提交 job_profile.slurm 到 cnall 后，仅在获分配的计算节点运行一条 Query。
- perf 可能被集群安全设置禁用。出现 Permission denied / perf_event_open 失败时保存日志，不尝试自行改 sysctl 或提权。
- 请勿把一个 Query 的性能剖析结果直接当作 6×8 的系统级瓶颈。后续需要针对并发情形复验。

## 单 Query 初步采样
从 `parallel-scan-20261028_230525/queries.txt` 中取中位附近的一条 Query，配置与正式搜索保持一致：`--cpu 8 --noali --F1 0.0005 --F2 5e-05 --F3 5e-07 -N 3 -E 0.001`。

运行 `job_profile.slurm` 时设置 PROFILE_BIN、PROFILE_DATA、PROFILE_SID。建议 PROFILE_BIN 指向上次完整 100 Query 的二进制快照，而不是当前开发目录中新编译的可执行文件。

输出包括：Slurm 日志 `profile.<JobID>.out`、`perf.data`、`perf-report.txt`、`jackhmmer.log`、独立的 `.tbl/.sto`。

## 重点判断
1. `perf-report.txt` 中的主要 DSO 与 symbol；是否集中在 `p7_Pipeline`、`impl_sse` 相关函数、序列 I/O 或建模步骤。
2. 若调用栈因编译时省略 frame pointer 而不完整，先做符号级热点分析；必要时再创建独立调试构建，切勿覆盖 baseline 二进制。
3. 如果没有 perf 权限，先记录 `perf --version`、`perf_event_paranoid`、错误信息，之后选择不需要提权的计时插桩。

与官方提交无关：perf 采样会引入开销，其墙钟时间不能拿去和 3518.5 秒直接比较。
