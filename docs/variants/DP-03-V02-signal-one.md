# DP-03/V02-signal-one — 工作队列唤醒改为 signal-one

- **开关**：`MSA_WQ_SIGNAL_ONE=1`（在创建队列时读取一次）
- **依赖**：无
- **状态**：proposed

## 假设

Reader 每放入一个块就调用 `pthread_cond_broadcast`，会唤醒所有等待中的 worker，但只有一个能拿到这个块（惊群效应）。
每次 8 个线程、6 个进程同时运行时，无效唤醒带来的上下文切换和锁竞争可能不小。改成 `pthread_cond_signal`，每个块只唤醒一个 worker。

## 改动

`easel/esl_workqueue.[ch]`：在 `esl_workqueue_Create()` 时读取开关；`ReaderUpdate()` 根据开关选择 signal 或 broadcast。

## 正确性

`tests/test_queue_signal_one.sh`：`--cpu 2/6` × `-N 1/3`，每种组合重复 3 次，命中表和 MSA 必须逐字节相同；每次运行限时 120 秒，用来发现死锁。

## 运行

| 运行 | 查询 | 节点 | job | A 总时间 | B 总时间 | 节省 | 配对 |
|---|---|---|---|---|---|---|---|

## 结论

待 q12 筛选。
