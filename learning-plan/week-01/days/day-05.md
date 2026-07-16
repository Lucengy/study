# Day 5：Server、RaftLog 与 StateMachine

## 目标

理解 Leader 接受写请求后，日志复制、commit、状态机 apply 的主路径。预计 3 小时。

## 任务

- [ ] 从 `RaftServerImpl` 的客户端请求处理入口开始，定位 Leader 分支和非 Leader 返回路径。
- [ ] 阅读 `LeaderStateImpl`、`LogAppenderBase`，只关注“追加本地日志、发给 follower、推进 commitIndex”三个问题。
- [ ] 阅读 `RaftLogBase`、`SegmentedRaftLog` 与 `StateMachineUpdater`，定位日志持久化及 committed entry 交给状态机的位置。
- [ ] 运行一个小目标测试：

  ```powershell
  .\mvnw.cmd -pl ratis-server -am -DskipTests=false -Dtest=LeaderElectionTests -Dsurefire.failIfNoSpecifiedTests=false test
  ```

- [ ] 在 `notes/day-05.md` 写一条写请求的时序：client request、leader append、follower append、majority、commitIndex、applyTransaction、reply。
- [ ] 对照 Day 3 的两个问题，写清“日志写入”“日志提交”“状态机应用”不是同一时刻。

## 完成标准

- 时序中的每一步至少关联一个真实类或方法。
- 能说明三节点集群为什么允许一台节点故障。
- 能指出状态机处理业务数据、RaftLog 处理复制日志，两者的边界。

