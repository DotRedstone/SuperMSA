# SuperMSA 仓库协作约定

开始修改前先读 `README.md` 和相关文档，并运行 `git status --short`。保留已有改动；一个功能使用一个短期分支，提交只包含同一目的的改动。提交信息使用带非空 scope 的 Conventional Commits，例如 `docs(architecture): 记录分支来源`。

## 代码与集成

- `main` 是稳定入口。功能分支从 `main` 创建；确需继承另一实验分支时，在 PR 和实验元数据中记录起点及依赖。不要为领域预建常驻集成分支。
- 不改写、强推或删除现有公开分支。旧分支与新分支的对应关系见 [迁移索引](docs/architecture/MIGRATION.md)。
- 保留根目录的 `prologue.sh`、`run_queries.sh`、`job_baseline.slurm` 等比赛入口。移动脚本前检查全部调用方及工作目录；不得为了整理目录改变搜索、评分或数据语义。
- 不使用 query 或数据库标注信息为搜索结果开捷径。预处理必须处于正式计时窗口内；正式得分时间为 `prologue time + search time`。
- 先验证构建、冒烟测试和正确性，再比较性能。性能结论应依据可追溯的多轮实验；构建成功或提交脚本 dry run 不等于正式运行通过。

## 集群与实验

- 登录节点只做轻量管理；编译和小测试在允许的测试节点执行，完整计算通过 Slurm。启动任务前检查集群规则和当前作业。
- 正在运行的作业所依赖的源码、二进制、输入、输出和工作目录不得移动或清理。未经核实的文件归为 `UNKNOWN` 并保留。
- 按 [实验规范](docs/experiments/INDEX.md)记录提交 SHA、构建参数、数据、Slurm 资源、完整日志、正确性和计时。原始日志不改写、不拼接；正式提交结果单独保存。
- 不提交凭据、私有部署值、比赛原始数据库、大型运行日志和生成的构建产物。除任务明确要求外，不更新依赖来源或锁文件。

项目结构与验证入口见 [仓库结构](docs/architecture/REPOSITORY.md)和[工作流程](docs/architecture/WORKFLOW.md)。
