# 仓库结构

本仓库的 `main` 保留官方 HMMER/JackHMMER 基线布局。`src/` 和 `easel/` 属于原有构建系统；在没有依赖审计与构建验证前不移动。根目录中的 `prologue.sh`、`run_queries.sh`、`job_baseline.slurm` 是比赛运行入口，`score.py` 是本地正确性评测入口。

| 位置 | 职责 |
| --- | --- |
| `src/` | HMMER 搜索、过滤与 jackhmmer 入口 |
| `easel/` | 序列、比对、I/O 等基础库 |
| `data/` | 仓库自带的演示数据；不是正式比赛数据 |
| `configure.ac`、`Makefile.in` | 原有构建入口 |
| 根目录比赛脚本 | 预处理、100 条 query 搜索、Slurm 作业与评分 |
| `docs/architecture/` | 仓库、分支、流程及迁移边界 |
| `docs/optimization/` | 技术任务索引；方案实现仍位于负责该行为的源码模块 |
| `docs/experiments/` | 实验编号、元数据规范及历史索引 |
| `tools/experiments/` | 实验索引、受控历史迁移及元数据模板 |
| `tests/` | 不依赖集群和正式数据的工具单元测试 |

现有性能分支还包含 `scripts/`、`tests/`、额外 Slurm 作业和实验文档。它们尚未集成到 `main`，不能按主线目录推断其文件清单。整理时优先把通用工具归入 `tools/db/`、`tools/build/` 或 `tools/runtime/`，把实验驱动和分析归入 `benchmarks/`；仅在确认调用关系后逐项移动。每次路径变更同时更新调用方、文档和验证命令。根目录比赛入口可保留为薄包装脚本。

不为规划中的组件创建空目录，也不复制解析器以匹配目录层级。结构调整与性能行为变更分开提交。
