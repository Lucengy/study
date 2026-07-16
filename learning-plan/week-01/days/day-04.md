# Day 4：Client 写请求链路

## 目标

从公开 API 跟到 RPC 发送前，理解同步/异步请求和 Leader 路由。预计 2～3 小时。

## 任务

- [ ] 阅读 `ratis-client/.../RaftClient.java` 的 builder、`io()`、`async()` 公共入口。
- [ ] 跟踪 `RaftClientImpl`、`OrderedAsync`，找到请求序号、pending request、重试与目标 peer 的处理位置。
- [ ] 从 `Assign.java` 的一次写请求开始，在 IDE 中使用 Call Hierarchy，记录到 gRPC client 的调用链；不要试图第一遍读完整个类。
- [ ] 在 `RaftClientImpl` 请求入口和 gRPC 发送处各设一个断点，运行 `TestArithmetic`，记录线程名、request callId、目标 peer。
- [ ] 搜索 `NotLeaderException` 的处理，回答：客户端从哪里得到新 Leader 信息？何时重试？
- [ ] 把链路写入 `notes/day-04.md`，每一跳写“类#方法 + 该方法只负责什么”。

## 完成标准

- 能给出从示例到 RPC 层的实际方法链，而不是只列模块名。
- 能解释 ordered async 为什么需要顺序和 pending 队列。
- 前一天“客户端如何找到 Leader”的猜测已被源码证据修正。

