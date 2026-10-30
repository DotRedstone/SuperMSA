# 服务器工作区

2026-10-30 现场整理：服务器工作区根目录下有 `SuperMSA/` 工作副本、`experiments/supermsa/`、`baselines/supermsa/`、`preliminary/` 和 `downloads/`。旧目录已在同一文件系统内按[迁移映射](../experiments/LEGACY_MIGRATION.md)重命名，规范实验实体位于 `experiments/supermsa/{dp,ck,qs,ev}/<task>/<variant>/<run-id>/`，历史附属文件位于 `assets/`。原 `probes/`、`runs/`、`analysis/` 及基线日志路径保留兼容链接。服务器源码工作副本原有的未提交改动未处理。以上是目录完整性检查，不代表正式运行验收。

## 目录原则

- 新实验建议使用 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/`，每轮保存独立元数据、原始日志和哈希。正式提交日志与探索性结果分开保存。
- 已结束的历史实验可按[迁移映射](../experiments/LEGACY_MIGRATION.md)原位重命名；旧路径用兼容链接保留，迁移清单记录逐项映射、inode 和文件数量。正在运行或排队作业所依赖的源码、二进制、输入、输出及工作目录视为受保护资源。
- 对文件标记 `ACTIVE`、`CANONICAL`、`HISTORICAL`、`DUPLICATE`、`TEMPORARY` 或 `UNKNOWN`。只有哈希、引用关系与作业状态均已核实，才可将内容标为重复或临时。`UNKNOWN` 不自动移动或删除。
- 不删除比赛数据库、query、评分文件、原始日志或正式提交结果；不取消作业。跨文件系统移动前检查磁盘配额、符号链接与硬编码路径，迁移前后校验哈希。

## 后续核对

当前索引见[实验记录](../experiments/INDEX.md)。全部实验区符号链接和旧索引视图均可解析；旧 `probes/` 顶层没有剩余实体实验，当前提交脚本会在规范目录下创建新运行。若将来需要回收大型预处理副本，须逐项核对内容哈希、作业和脚本引用，并保留可复现的生成方式与回退路径；目前未核实这些条件。私有主机名、账号、内部地址及凭据不写入仓库。
