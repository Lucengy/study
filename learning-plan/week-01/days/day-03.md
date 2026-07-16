# Day 3：从 Arithmetic 示例理解 Ratis

## 目标

用最小示例建立 RaftGroup、Server、Client、StateMachine 的整体认识。预计 2～3 小时。

## 任务

- [ ] 阅读 `ratis-examples/README.md` 的 Arithmetic 部分。
- [ ] 按顺序阅读：`examples/common/Runner.java`、`arithmetic/cli/Server.java`、`arithmetic/cli/Assign.java`、`ArithmeticStateMachine.java`。
- [ ] 搜索并记录 `RaftGroup`、`RaftPeer`、`RaftServer.newBuilder()`、`RaftClient.newBuilder()` 在示例中的创建位置。
- [ ] 运行 `TestArithmetic`：

  ```powershell
  .\mvnw.cmd -pl ratis-examples -am -DskipTests=false -Dtest=TestArithmetic -Dsurefire.failIfNoSpecifiedTests=false test
  ```

- [ ] 在 `notes/day-03.md` 画出 `Assign -> RaftClient -> 三个 RaftServer -> ArithmeticStateMachine` 组件图，标注“配置”“网络”“持久化”“业务状态”分别归谁负责。
- [ ] 写下三个问题：客户端如何找到 Leader？日志何时提交？状态机何时执行？先写你的猜测，后两天用源码校正。

## 完成标准

- `TestArithmetic` 通过，或已定位到明确环境/代码错误。
- 能用自己的话区分 Raft 日志与业务状态机。
- 组件图至少包含 Client、RaftGroup、RaftServer、RaftLog、StateMachine。

