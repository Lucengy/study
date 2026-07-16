# Day 7：小改动、验证与复盘

## 目标

完成一次安全的小修改，走完 Windows 开发、测试、Git 同步、Linux 验证闭环。预计 2～3 小时。

## 任务

- [ ] 从以下两项选一项：A. 为 Arithmetic 非法表达式补一个测试；B. 在 Counter/Arithmetic 的关键状态机路径增加一条有用且不过量的 debug 日志。
- [ ] 修改前先写预期；修改后在 Windows 运行对应模块的单测，再运行 `TestArithmetic` 回归。
- [ ] 用 `git diff --check` 检查空白问题，用 `git diff` 自审，只提交与本实验有关的文件。
- [ ] commit message 说明意图，如 `test(examples): cover invalid arithmetic expression`。
- [ ] 运行同步脚本，在三台 CentOS 拉取相同 commit；至少选一台执行同一测试，确认跨平台结果。
- [ ] 填写 `notes/week-summary.md`：本周最重要的三点、仍不清楚的三个问题、下周计划阅读的三个类。
- [ ] 将组件图和写请求时序各修订一遍，确保它们来自源码和实验，而不是最初猜测。

## 完成标准

- 有一个范围小、可解释、带测试证据的 commit。
- Windows 和至少一台 CentOS 的目标测试都通过，commit id 一致。
- 周总结中明确写出下周入口，建议继续深入选举、日志复制和快照。

