# Day 4：从一条同步写请求理解 Ratis Client

## 今天为什么重新设计

Day 3 只回答了“客户端大致会找到 Leader”。今天不直接钻进所有 Client 源码，而是从 Arithmetic 的一条真实语句开始：

```java
client.io().send(new AssignmentMessage(...));
```

先跟完**同步写请求**，再研究 Leader 更新，最后才把它和异步请求比较。不要同时阅读 `BlockingImpl`、`OrderedAsync`、gRPC 全部实现。

预计用时：5～7 小时，不要求一天连续完成。可以拆成三次：阶段一至三约 2～3 小时；
阶段四的 4.1～4.4 约 1～2 小时；阶段四的 4.5～4.8 与阶段五约 2 小时。

---

## 完成后你应当能回答

1. Arithmetic 示例中的 `Client`、`RaftClient`、`RaftClientImpl`、`RaftClientRpc` 分别是谁？
2. `Assign.operation()` 如何走到 `GrpcClientRpc.sendRequest()`？
3. 一个 `RaftClientRequest` 至少包含哪些身份信息？
4. 客户端第一次为什么可能发错节点？
5. Follower 如何告诉客户端“我不是 Leader”？客户端怎样换目标并重试？
6. `io().send()` 与 `async().send()` 的入口、返回值和 RPC 方法有什么区别？
7. `OrderedAsync` 为什么需要 Future、pending request、`seqNum` 和滑动窗口？
8. 异步请求怎样限制在途数量，并在换 Leader 或 RPC 异常后继续重试？

---

# 阶段零：先把五个 Client 名称摆正

这一阶段只建立对象关系，不跟方法。

| 名称 | 所在模块/包 | 本例中的职责 |
| --- | --- | --- |
| `arithmetic.cli.Client` | `ratis-examples` | 示例抽象命令类，解析公共参数并创建 `RaftClient` |
| `RaftClient` | `ratis-client` | Ratis 对业务代码公开的客户端接口 |
| `RaftClientImpl` | `ratis-client.impl` | `RaftClient` 的实际实现，保存 group、leader、retry 等状态 |
| `BlockingImpl` | `ratis-client.impl` | 实现 `client.io()` 返回的同步 API |
| `RaftClientRpc` / `GrpcClientRpc` | `ratis-client` / `ratis-grpc` | RPC 抽象及本例实际使用的 gRPC 实现 |

按顺序打开，不要展开整个类：

1. `ratis-examples/.../arithmetic/cli/Client.java`：只看 `run()`。
2. `ratis-client/.../RaftClient.java`：只看 `io()`、`async()` 和 `Builder.build()`。
3. `ratis-client/.../RaftClientImpl.java`：只看构造方法、`io()`、`async()`。
4. `ratis-client/.../BlockingImpl.java`：只看两个 `send` 和 `sendRequest`。

### 阶段零检查点

不看源码，用自己的话回答：

1. 示例的抽象 `Client` 会不会直接发送 gRPC？
2. `RaftClient client` 的声明类型与运行时实现类型分别是什么？
3. `RaftClientRpc` 与 `RaftClient` 是不是同一层对象？

答不清时不要进入下一阶段。

---

# 阶段一：只跟同步请求，不看异步

## 1.1 起点：Assign 只负责业务消息

打开：

```text
ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/cli/Assign.java
```

找到 `operation(RaftClient client)`：

```java
RaftClientReply send = client.io().send(
    new AssignmentMessage(new Variable(name), createExpression(value)));
```

先回答：

- `Assign` 把什么业务数据装进 `AssignmentMessage`？
- 此处有没有 serverId、callId、groupId？
- 这行代码是否知道底层使用 gRPC？

预期结论：`Assign` 只构造业务消息并选择同步 API，不负责组装完整 Raft 请求，也不直接处理网络。

## 1.2 `io()` 把接口入口接到同步实现

依次跳转：

```text
RaftClient#io()
RaftClientImpl#io()
```

注意两种“类型”：

```text
接口声明返回：BlockingApi
实际返回对象：BlockingImpl
```

这里复用了你在 JCommander Lab 中已经见过的“接口/抽象类型统一入口，实际对象完成工作”的思路。

## 1.3 `BlockingImpl` 的三层方法不要压成一个

在 `BlockingImpl` 中按顺序只看：

```text
send(Message)
  -> send(Type, Message, RaftPeerId)
     -> sendRequestWithRetry(...)
        -> sendRequest(RaftClientRequest)
```

分别写出每层只负责什么：

| 方法 | 只关注的职责 |
| --- | --- |
| `send(Message)` | 把调用定义成哪种请求类型 |
| 私有 `send(...)` | 生成 callId，准备构造请求 |
| `sendRequestWithRetry(...)` | 保存一次逻辑请求的重试状态并循环尝试 |
| `sendRequest(RaftClientRequest)` | 第一次调用 `RaftClientRpc` |

不要在这里阅读所有异常分支。

## 1.4 第一次越过模块边界

找到：

```java
client.getClientRpc().sendRequest(request);
```

再回到示例 `Client.run()`，确认它显式调用：

```java
new GrpcFactory(...).newRaftClientRpc(...)
```

所以运行时分派关系是：

```text
RaftClientRpc.sendRequest
          |
          v
GrpcClientRpc.sendRequest
```

### 阶段一作业

在 `notes/day-04.md` 写出下面这条链，每一跳后只写一句职责：

```text
Assign#operation
  -> RaftClientImpl#io
  -> BlockingImpl#send(Message)
  -> BlockingImpl#send(Type, Message, RaftPeerId)
  -> BlockingImpl#sendRequestWithRetry
  -> BlockingImpl#sendRequest
  -> GrpcClientRpc#sendRequest
```

### 阶段一检查点

1. `client.io().send()` 是同步还是异步？“同步”具体阻塞在哪里？
2. 哪个方法第一次创建 callId？
3. 哪个方法第一次调用 `RaftClientRpc`？
4. 为什么 `Assign` 源码不依赖 `GrpcClientRpc` 类，运行时却能使用它？

---

# 阶段二：拆开 RaftClientRequest

## 2.1 找到完整请求的创建处

打开：

```text
RaftClientImpl#newRaftClientRequest(...)
```

只记录下面字段的来源，不必研究 Builder 的其他方法：

| 字段 | 回答“从哪里来” |
| --- | --- |
| `clientId` |  |
| `groupId` |  |
| `callId` |  |
| `serverId/leaderId` |  |
| `message` |  |
| `type` |  |

## 2.2 理解 callId 与 attemptCount 不相同

观察：

```text
BlockingImpl 中 callId 在进入重试循环前生成
PendingClientRequest 中 attemptCount 每次 newRequest() 增加
```

先预测：一次请求第一次发给 n0，失败后重试到 n1，callId 应该变化还是保持？attemptCount 呢？

正确方向是：callId 标识同一个逻辑请求，重试次数由 attemptCount 记录。否则 Server 难以识别“新请求”还是“同一请求重试”。

### 阶段二检查点

1. `AssignmentMessage` 与 `RaftClientRequest` 是什么关系？
2. `server == null` 时，`newRaftClientRequest()` 把目标设成谁？
3. 同一次逻辑请求重试时，为什么不能随意产生新的 callId？

---

# 阶段三：客户端不是先“探测”，而是先选一个目标

## 3.1 初始 Leader 从哪里来

阅读 `RaftClientImpl#computeLeaderId(...)`，只总结优先顺序：

```text
Builder 显式传入的 leaderId
  -> 该 group 的 Leader 缓存
  -> RaftGroup 中优先级最高的 peer
```

这一步选择的是“当前准备发送的目标”，不保证它一定是真实 Leader。

## 3.2 发错节点会发生什么

在工程中搜索：

```text
NotLeaderException
suggestedLeader
```

先只跟这一条处理链：

```text
Server/Follower 返回 NotLeaderException
  -> reply 中可能携带 suggestedLeader 和 peersInConf
  -> RaftClientImpl#handleNotLeaderException
  -> 更新 peers/leaderId
  -> BlockingImpl 根据 RetryPolicy 再次构造并发送请求
```

重点看：

```text
RaftClientImpl#handleNotLeaderException
RaftClientImpl#handleIOException
RaftClientImpl 中 leaderId 被重新赋值的位置
```

### 修正 Day3 猜测

把 Day3 的“RaftClient 负责寻找 Leader”改写得更精确：

```text
RaftClient 先按显式配置、缓存或 peer 优先级选择目标；
若目标不是 Leader，Follower 通过 NotLeaderException 返回 suggestedLeader；
客户端更新 leaderId，并按重试策略重新发送同一个逻辑请求。
```

### 阶段三检查点

1. 新 Leader 信息由客户端自己计算出来，还是由 Server 回复提供？
2. `suggestedLeader == null` 时客户端是否完全无法继续？请从代码中找证据。
3. 更换目标后，callId 与 attemptCount 分别怎样变化？

---

# 阶段四：循序渐进地跟异步请求

前面已经跟完同步链路，这一阶段才进入异步链路。不要一开始通读 `OrderedAsync` 和
`SlidingWindow`；按照“入口与 Future → 主调用链 → pending request → 有序窗口 →
并发与重试”的顺序阅读。

本阶段的答案统一填写到 `notes/day-04.md` 的“异步链路”部分。记录文件已经按题号
预留了答案区。

## 4.1 入口对照

```text
同步：client.io().send(message)
异步：client.async().send(message)
```

同步返回：

```text
RaftClientReply
```

异步返回：

```text
CompletableFuture<RaftClientReply>
```

只阅读：

```text
RaftClient#async()
RaftClientImpl#async()
AsyncImpl 类声明、构造方法和 send(Message, ReplicationLevel)
```

回答：

1. 外部变量 `client` 的声明类型和实际实现类型分别是什么？
2. `RaftClient#async()` 的声明返回类型是什么？实际返回对象是什么类？
3. `AsyncImpl` 内部保存的 `client` 字段是什么类型？它与外部的 `client` 是不是同一个对象？
4. 为什么 `send()` 返回 `CompletableFuture<RaftClientReply>`，而不是直接返回 `RaftClientReply`？
5. 执行下面第一行后，是否代表 Server 已经处理完成？下面三种写法分别在哪里等待结果？

```java
CompletableFuture<RaftClientReply> future = client.async().send(message);
future.thenAccept(reply -> System.out.println(reply));
RaftClientReply reply = future.join();
```

检查点：能够用自己的话解释“Future 是未来结果的容器”，并区分“提交请求”和
“取得最终响应”。

## 4.2 只看异步主干

```text
RaftClientImpl#async
  -> AsyncImpl#send
  -> OrderedAsync#send
  -> OrderedAsync#sendRequestWithRetry
  -> RaftClientRpc#sendRequestAsync
  -> GrpcClientRpc#sendRequestAsync
```

只阅读：

```text
AsyncImpl#send(Message, ReplicationLevel)
AsyncImpl#send(Type, Message, RaftPeerId)
OrderedAsync#send(...)
OrderedAsync#sendRequestWithRetry(...)
```

回答：

1. `AsyncImpl.send(Message, ReplicationLevel)` 创建的是哪一种请求类型？
2. 普通异步写请求交给 `OrderedAsync` 还是 `UnorderedAsync`？写出源码证据。
3. `callId` 在哪个类的哪个方法中产生？
4. `seqNum` 在哪里分配？
5. `RaftClientRequest` 最终在哪个方法中构建？重试时会不会再次构建？
6. 异步链路中哪个方法第一次调用 `RaftClientRpc`？调用的具体方法是什么？
7. 补全并解释下面的调用链，每一跳只写一句职责：

```text
RaftClientImpl#async
  -> __________#send
  -> RaftClientImpl#get________Async
  -> __________#send
  -> __________#sendRequestWithRetry
  -> RaftClientRpc#________________
  -> GrpcClientRpc#________________
```

## 4.3 先理解 pending request，不急着读完整窗口

阅读 `OrderedAsync.PendingOrderedRequest` 和 `OrderedAsync#send(...)`，回答：

1. `PendingOrderedRequest` 为什么叫 pending？它表示已经完成的请求，还是尚未完成的请求？
2. 它保存了哪些重要信息？至少找到 `callId`、`seqNum`、请求构造器、Future 和 `isFirst`。
3. `OrderedAsync#send(...)` 最终返回的 Future 来自哪里？
4. RPC 回复到达后，程序怎样找到并完成“这个请求自己的 Future”？
5. 假设发送顺序为 `1 → 2 → 3`，回复顺序为 `3 → 1 → 2`，请求 3 的 Future
   会不会错误地拿到请求 1 的回复？为什么？

此时只要求理解：每个在途请求都有自己的状态和 Future；不要提前研究
`SlidingWindow` 的所有泛型与分支。

## 4.4 为什么需要 ordered、callId 和 seqNum

假设业务连续异步发送：

```text
x = 1
x = x + 1
get x
```

网络完成顺序可能与提交顺序不同。`OrderedAsync` 使用序号、滑动窗口和 pending request：

- 给同一客户端的有序请求编号；
- 限制同时在途的请求数量；
- 保存尚未完成请求对应的 Future；
- 在重试、回复乱序时仍维护请求顺序和完成关系。

本周只需要解释“为什么存在”，不要求掌握滑动窗口全部实现。

先填写对照表：

| 对比项 | `callId` | `seqNum` |
| --- | --- | --- |
| 在哪里产生 |  |  |
| 主要用途 |  |  |
| 是否属于滑动窗口 |  |  |
| 重试时是否改变 |  |  |
| 是否用于表达窗口内顺序 |  |  |

再回答：

1. 已经有了 `callId`，为什么还需要 `seqNum`？分别从“请求身份”和“窗口顺序”解释。
2. “有序异步”是不是说必须等请求 1 完成后，才能发送请求 2？
3. 多个请求能不能同时处于网络传输中？
4. “有序”保证的是发送串行、网络回复顺序，还是逻辑请求的顺序管理？

## 4.5 只阅读 SlidingWindow 的五个位置

打开 `SlidingWindow.Client`，本轮只找：

```text
nextSeqNum
firstSeqNum
requests
delayedRequests
submitNewRequest(...)
receiveReply(...)
```

回答：

1. `nextSeqNum` 的初始值是什么？新请求提交时怎样变化？
2. `requests` 和 `delayedRequests` 分别保存什么？
3. `firstSeqNum` 与请求中的 `isFirst` 有什么关系？
4. `receiveReply()` 为什么必须能够处理乱序到达的回复？
5. 回复先到是否等于业务请求可以越过前面的请求执行？客户端窗口管理和
   Raft Server 的日志提交顺序是不是同一个概念？

## 4.6 并发限制：异步不等于入口绝不等待

回到 `OrderedAsync#send(...)`，观察 `requestSemaphore`：

1. 为什么发送前调用 `requestSemaphore.acquire()`？
2. 为什么要在 Future 完成后的 `whenComplete(...)` 中调用 `release()`？
3. 假设最多允许 100 个未完成请求，第 101 次调用 `send()` 时会发生什么？
4. 因此，“异步 API 在任何情况下都不会阻塞调用线程”这句话是否准确？

注意区分：通常不等待 RPC 最终回复，与因为并发额度耗尽而暂时等待，不是同一件事。

## 4.7 异步重试

只阅读：

```text
OrderedAsync#sendRequestWithRetry(...)
OrderedAsync 中处理异常和安排重试的方法
RaftClientImpl#handleNotLeaderException(...)
```

回答：

1. `sendRequestAsync()` 返回 Future 后，RPC 异常从哪里进入重试处理？
2. 哪个对象决定是否重试、等待多久以及何时停止？
3. 遇到 `NotLeaderException` 时，客户端会更新什么？为什么还可能重置滑动窗口？
4. 重试时 `callId`、`seqNum`、`attemptCount` 和目标 Server 分别可能怎样变化？
5. 为什么重试不能被当成一个全新的逻辑请求，随意分配新的 `callId` 和 `seqNum`？
6. 哪些情况下返回给调用者的 Future 会以异常结束？

## 4.8 同步与异步综合检查点

先填写 `notes/day-04.md` 中的同步/异步对照表，再回答：

1. `Assign` 当前实际走同步还是异步路径？
2. 为什么不能从 `Assign` 直接声称它经过了 `OrderedAsync`？
3. `CompletableFuture` 是否等于“自动为每次调用创建一个新线程”？
4. 调用 `future.join()` 后，调用者是否又发生了等待？
5. 有序异步是否意味着同一时刻只能有一个请求在途？
6. 网络回复可以乱序到达时，每个 Future 为什么仍能得到自己的回复？
7. 客户端的 ordered async 是否意味着 Raft Server 可以无序执行日志？

最后分析场景：

```text
请求 1：x = 1
请求 2：x = x + 1
请求 3：读取 x
```

回答：三个请求能否都在请求 1 回复前提交？RPC 回复能否乱序到达？请求 3 能否因为
回复先到就越过请求 2 执行？客户端有序窗口与 Raft 日志顺序分别负责什么？

### 阶段四完成顺序

不要一次写完。按下面顺序提交检查：

1. 先完成 4.1：异步入口和 Future。
2. 再完成 4.2：异步主调用链。
3. 然后完成 4.3～4.4：pending、callId 与 seqNum。
4. 再完成 4.5：只读滑动窗口的指定位置。
5. 最后完成 4.6～4.8：并发限制、重试和综合对照。

`TestArithmetic` 走的是 `client.io()` 同步链路，因此不会命中 `AsyncImpl` 或
`OrderedAsync` 的断点。阶段四先以静态源码证据为准，异步动态实验后续单独进行。

---

# 阶段五：断点实验（先静态、后动态）

如果 IDEA 已能正常调试 Maven 测试，再做本阶段；否则保存静态调用链也算有效进度。

## 5.1 建议只设三个断点

1. `BlockingImpl#send(Type, Message, RaftPeerId)`：观察新 callId。
2. `RaftClientImpl#newRaftClientRequest` 返回前：观察 clientId、groupId、serverId、callId、type。
3. `GrpcClientRpc#sendRequest(RaftClientRequest)`：观察最终目标 peer。

不要第一遍在异步回调和 Server 内同时设大量断点。

## 5.2 运行测试

在 Ratis 根目录执行：

```powershell
.\mvnw.cmd -pl ratis-examples -am `
  "-DskipTests=false" `
  "-Dtest=TestArithmetic" `
  "-Dsurefire.failIfNoSpecifiedTests=false" `
  test
```

注意：`TestArithmetic` 不会调用 CLI 类 `Assign#operation`。测试在自己的 `assign(...)` 辅助方法中直接调用同样的：

```java
client.io().send(...)
```

因此它能验证从 `RaftClient` 开始的同步链，但不要等待 `Assign#operation` 断点命中。真正的 CLI `Assign` 会在 Day6 运行 `client.sh arithmetic assign` 时使用。

如果使用 IDEA Debug 测试，至少记录一次命中的：

| 观察项 | 值 |
| --- | --- |
| 当前线程名 |  |
| request type |  |
| callId |  |
| groupId |  |
| target serverId |  |

测试可能创建多个 client/request，不要求所有断点的 callId 相同。只选择其中一次写请求贯穿记录。

---

# Day 4 最终作业

写入 `notes/day-04.md`：

1. 五种 Client/实现对象关系表。
2. 同步写请求方法链，每一跳一句职责。
3. `RaftClientRequest` 六个关键字段的来源。
4. 初始目标选择顺序。
5. `NotLeaderException -> 更新 Leader -> 重试` 的证据链。
6. 阶段四 4.1～4.8 的异步链路答案及同步/异步对照。
7. 用自己的话回答：ordered async 为什么需要序号、pending request 和并发限制？
8. 三个同步链路断点观察；如果暂时无法 Debug，写清阻塞原因和静态源码证据。

## 完成标准

- 能明确说出题目中的“客户端”主要指 `RaftClient/RaftClientImpl`，而不是示例抽象 `Client`。
- 能从 `Assign#operation` 走到 `GrpcClientRpc#sendRequest`，不混入异步类。
- 能解释客户端不是预先保证找到 Leader，而是通过目标选择、NotLeader 回复和重试逐步校正。
- 能说明同步与异步是两条不同实现链，`Assign` 当前使用同步链。
- 能解释 callId、attemptCount、pending request 各自解决的问题。

完成 Day4 后再进入 Day5。Day5 将从 `GrpcClientRpc` 的另一端开始，只跟 Server 收到一条写请求后的生命周期。
