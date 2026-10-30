# SuperMSA 仓库维护约定

开始前阅读 `README.md`、相关目录文档，并运行 `git status --short`。保留已有未提交文件；只修改本任务涉及的内容。

## 分支与提交

- `main` 是稳定入口。代码分支使用 `<类型>/<小写任务号>/<功能名>`，例如 `perf/dp-01/direct-map`；跨任务文档和仓库整理使用 `docs/<名称>` 或 `refactor/<名称>`。每项修改通常从 `main` 创建短期分支；确需继承其他实验分支时，在 PR 中写明起点与依赖。历史分支改名和旧引用处理见 [迁移说明](docs/architecture/MIGRATION.md)。
- 一个提交只承担一个目的。行为变更、目录迁移和纯文档整理分别提交。提交信息使用带非空 scope 的 Conventional Commits，英文类型、中文描述，例如 `fix(reader): 修复空输入处理`。
- PR 写明变更范围、验证命令及结果、回退方式。未经正确性验证的性能候选不得直接进入 `main`。分支及集成流程见 [分支规范](docs/architecture/BRANCHING.md)和[工作流程](docs/architecture/WORKFLOW.md)。

## 代码与测试脚本

- 保留比赛入口 `prologue.sh`、`run_queries.sh` 及正式作业脚本的调用路径。移动辅助脚本时同步检查调用方、工作目录和相对路径；不为目录整理改动搜索或评分语义。
- 可复用工具放在 `tools/`，实验作业与分析按 [仓库结构](docs/architecture/REPOSITORY.md)存放。自动检查放在 `tests/`：使用小型合成样例、明确断言和非零失败退出码；默认不访问网络、不提交 Slurm 作业、不读取正式比赛数据。测试数据不得包含个人部署值或真实运行数据。
- 修改 Python 或 Bash 脚本至少执行 `python3 -m py_compile <脚本>` 或 `bash -n <脚本>`；涉及行为的修改运行 `python3 -m unittest discover -s tests -p 'test_*.py'` 中相关测试。可在允许的测试节点运行构建与 `smoke_test.sh`；完整正确性和性能实验通过 Slurm 运行，并按[实验规范](docs/experiments/INDEX.md)留存原始证据。语法检查、合成测试和构建成功均不等于正式 100-query 验收。

## 实验与服务器

- 新实验使用 `experiments/supermsa/<domain>/<task>/<variant>/<run-id>/`，每轮记录源码、构建、数据、资源、日志、正确性与计时。正式时间包括预处理和搜索；不得利用 query 或数据库标注绕过搜索。
- 登录节点只做轻量管理。整理服务器文件前核对 Slurm 作业和引用；运行中的作业依赖不可移动。原始日志和评分结果不改写；不提交凭据、私有地址、比赛数据库、大型日志或构建产物。服务器布局与迁移方式见[工作区说明](docs/architecture/SERVER_WORKSPACE.md)。
