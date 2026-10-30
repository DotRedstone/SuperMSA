# 分支迁移记录

2026-10-30 将远端旧分支按[任务号命名规范](BRANCHING.md)迁移。下表的 SHA 是迁移时的分支 HEAD；重命名没有改写提交历史，也没有将性能候选合入 `main`。原名用于查找旧报告，后续开发使用新名。GitHub 旧分支 URL 会重定向；本地已有克隆需运行 `git fetch origin --prune` 并改用新分支名。

| 原远端分支 | 当前分支或处理结果 | 迁移时 HEAD |
| --- | --- | --- |
| `feat/query-parallel-scheduler` | `feat/qs-01/query-parallel-scheduler` | `d0fa3707c1cfbfd9972e920af6d8528c7192c342` |
| `release/v1-query-parallel-p6t8` | 与上述分支同 HEAD，删除重复引用；未经正式验收，不创建发布 tag | `d0fa3707c1cfbfd9972e920af6d8528c7192c342` |
| `perf/fasta-preprocess` | `perf/dp-01/preprocess` | `665f1e75335975654bac8132f56f1c31291c7572` |
| `perf/fasta-onepass-t1` | `perf/dp-01/onepass` | `34290cc7fae4bc671e2a79005bb9cd0849559e55` |
| `perf/fasta-direct-map-e05` | `perf/dp-01/direct-map` | `2f7e9d597ca729544eceb3af9db8a068d909c373` |
| `perf/fasta-config-cache-e06` | `perf/dp-01/config-cache` | `f6a0caadf3899f81451928089b1ddd45b80dc5d0` |
| `perf/fasta-chunk-64k-e07` | `archive/dp-01/chunk-64k-e07`；由新的独立候选取代 | `10602851a2a3f958661c7bffdd679d18d381a656` |
| `perf/dp/fasta-read-chunk-64k` | `perf/dp-01/chunk-64k`；草稿 PR #6 改由 [PR #7](https://github.com/DotRedstone/SuperMSA/pull/7) 继续 | `551f69a0924873c4732d3d17ebca76110856859b` |
| `perf/binary-sequence-db` | `perf/dp-02/binary-sequence-db` | `5c3b37de28bac9e7faee2f155ef49c34a9e2ca31` |
| `perf/db-huffman` | `perf/dp-02/huffman` | `7942acab890c9031e46e9c5157406a7d41a4ef36` |
| `perf/db-four-way` | `perf/dp-02/four-way`；同时作为 EV-01 历史比较的来源 | `9dcea8b0418a6dabfc4a5da989afd85a3ecd54d8` |
| `perf/bin8-batched-io-t2` | `perf/dp-03/batched-io` | `85868e203a398707c17811e4fc5f3817acc2767c` |
| `perf/reader-queue-t3` | `perf/dp-04/reader-queue` | `fa7aed6a4a861179a58010d28068d8dacb0bae6c` |
| `perf/queue-signal-one-t4` | `perf/dp-05/signal-one` | `a835585f23472a311a4652c526fea7ee6b9ffd47` |
| `perf/ssv-band-limit` | `perf/ck-01/ssv-band-limit` | `6eef9eb11f6a1fcffd4d3215baf1b7507566cb12` |
| `perf/abba-analysis-r02` | `bench/ev-01/abba-analysis` | `49570c194e57475910981f5f33b5426e893cf25a` |
| `perf/reader-worker-profile-t5` | `probe/ev-02/reader-worker` | `d74d87465bdc53a04ce1a9490e42acfcb62c86b5` |
| `perf/jackhmmer-hotspots` | `probe/ev-03/jackhmmer-hotspots` | `c0b7300a6dbe3b3a7a24f18aeceb52d6e3164055` |

`main` 仍是默认分支。迁移时 HEAD 为 `6aeebaea46724b69b87031efbd309e01a3714457`；分支迁移未修改它。`DP-01` 的 E06 与 E07 旧提交都继承 E05，E07 不继承 E06。新的 `perf/dp-01/chunk-64k` 从当前 `main` 单独实现，与旧 E07 是两条提交链。其余旧分支的继承关系须由 Git 提交图确认，不能由新名称推断。

如果需要恢复某个旧分支名，可用本表的 SHA 创建引用；不要重写提交。旧实验目录与原始日志仍按[服务器迁移记录](../experiments/LEGACY_MIGRATION.md)保留，分支名迁移不改变其内容。目录或分支名称均不证明正式正确性或性能验收。

服务器 `SuperMSA/` 工作副本原先停在本地 `feat/query-parallel-scheduler`，HEAD 为基线提交 `2f85a28`，包含未提交的混合实验改动；它不是上表远端 QS-01 分支的 HEAD。该本地分支改名为 `wip/legacy-server`，工作树内容保持原状，后续需按任务拆分并重新验证。
