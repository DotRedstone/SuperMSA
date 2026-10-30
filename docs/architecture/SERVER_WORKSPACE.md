# 服务器工作区

2026-10-30 现场核对：`WORK/dot` 下有 `SuperMSA/` 工作副本、`experiments/supermsa/`、`baselines/supermsa/`、`preliminary/` 和 `downloads/`。旧实验主要位于 `experiments/supermsa/probes/`，约 148 GB；`runs/` 约 113 MB。探针中存在多个十 GB 级预处理数据库副本，不能仅凭文件名或大小认定内容相同。旧 `t1` 至 `t5` 入口中有 9 个是指向 `probes/experiments/` 的符号链接。当前服务器工作副本有未提交的源码、脚本及构建文件，整理实验时不得重置或清理该副本。上述是目录与状态观察，不代表正式运行验收。

## 目录原则

- 新实验建议使用 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/`，每轮保存独立元数据、原始日志和哈希。正式提交日志与探索性结果分开保存。
- 已结束的历史实验可按[迁移映射](../experiments/LEGACY_MIGRATION.md)原位重命名；旧路径用兼容链接保留，迁移清单记录逐项映射、inode 和文件数量。正在运行或排队作业所依赖的源码、二进制、输入、输出及工作目录视为受保护资源。
- 对文件标记 `ACTIVE`、`CANONICAL`、`HISTORICAL`、`DUPLICATE`、`TEMPORARY` 或 `UNKNOWN`。只有哈希、引用关系与作业状态均已核实，才可将内容标为重复或临时。`UNKNOWN` 不自动移动或删除。
- 不删除比赛数据库、query、评分文件、原始日志或正式提交结果；不取消作业。跨文件系统移动前检查磁盘配额、符号链接与硬编码路径，迁移前后校验哈希。

## 后续核对

[`catalog.py`](../../tools/experiments/catalog.py) 为迁移后的规范目录生成索引与符号链接视图；旧路径由兼容链接保持可用。若将来需要回收大型预处理副本，须逐项核对内容哈希、作业和脚本引用，并保留可复现的生成方式与回退路径；目前未核实这些条件。私有主机名、账号、内部地址及凭据不写入仓库。
