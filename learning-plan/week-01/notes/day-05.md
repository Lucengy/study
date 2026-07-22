# Day 5 记录：一条写请求在 Server 中经历了什么

> 填写方式：按照手册阶段逐节完成。答案尽量写“源码位置 + 自己的解释”，不要只抄方法名。

## 0.1 开始前的五条预测

1. 收到请求是否等于写入日志？

    1. 收到请求，不等于写入日志。

2. Leader 本地写入是否等于多数派复制？

   写入 Leader 本地日志，不等于复制到多数派。

3. 多数派复制是否要求三台全部完成？

   复制到多数派，不等于每台机器都已经复制。

4. commitIndex 推进是否等于状态机已经 apply？

   日志提交，不等于状态机此前已经执行。

5. Client 成功 reply 与状态机结果是什么关系？

   状态机执行完成，才产生本例的业务结果并完成 Client reply。

## 0.2 六个角色

| 角色 | 本阶段职责 | 它不负责什么 |
| --- | --- | --- |
| `RaftServerProxy` |  |  |
| `RaftServerImpl` |  |  |
| `LeaderStateImpl` |  |  |
| `RaftLog` |  |  |
| `LogAppender` |  |  |
| `StateMachineUpdater` |  |  |

1. `RaftServerImpl` 与 `LeaderStateImpl` 是不是同一个对象？

   **我的答案：**

2. `RaftLog` 与 `ArithmeticStateMachine.variables` 保存的是不是同一种数据？

   **我的答案：**

## 1.1 请求入口与类型分派

1. `RaftServerProxy` 为什么要先根据 groupId 找 Division？

   因为ratis支持multi-raft，一个RatisServerProxy存在多个group，所以要先根据groupId分发到对应的Division中

2. `replyFuture()` 根据什么把请求分派到 `writeAsync()`？

   根据TypeCase，若为WRITE/FORWARD，会分发到writeAsync()方法中

3. 请求刚进入 `submitClientRequestAsyncInternal()` 时是否已经生成日志 term/index？

   请求刚进入 submitClientRequestAsyncInternal() 时还没有生成 Raft 日志的 term/index。Leader 在执行本地日志追加时，由 ServerState.appendLog() 把当前 term 传给 RaftLogBase.append()；RaftLogBase.appendImpl() 通过 getNextIndex() 得到新日志的 index，然后调用 TransactionContext.initLogEntry(term, nextIndex) 构造包含 term/index 的 LogEntryProto。SegmentedRaftLog.appendEntryImpl() 接收到的已经是构造完成的日志项。

补全调用链，并给每一跳写一句职责：

```text
RaftServerProxy#submitClientRequestAsync // 根据groupID，将请求分发到对应的RaftServerImpl中
  -> RaftServerImpl#submitClientRequestAsync // 对请求加入链路跟踪
  -> RaftServerImpl#submitClientRequestAsyncInternal // 加入请求的处理时间和处理情况的统计信息
  -> RaftServerImpl#replyFuture // 根据TypeCase分发请求
  -> RaftServerImpl#writeAsync // 调用 writeAsyncImpl；对于 WRITE 请求，根据 ReplicationLevel 决定是否继续等待指定复制级别
  -> RaftServerImpl#writeAsyncImpl // 进入写请求核心流程，首先检查当前节点的 Leader 状态，然后才可能处理事务和日志追加
```

## 1.2 Leader 检查

1. `checkLeaderState()` 返回 `null` 表示什么？
   * 当前节点是 Leader；
   * Leader 已经 ready；
   * 当前没有处于 stepping down 状态。

2. 当前节点不是 Leader 时返回什么？suggestedLeader 和 peers 有什么用途？

   当前节点不是 Leader 时，返回一个正常完成的 CompletableFuture<RaftClientReply>，但 RaftClientReply 中携带 NotLeaderException。
   suggestedLeader 是服务端当前认为的 Leader 对应的 RaftPeer，客户端可以优先向它重试；如果服务端也不知道 Leader，它可能为 null。
   peers 是当前 Raft 配置中的节点集合，客户端可以据此更新自己保存的集群节点列表

3. Leader not ready 与 stepping down 时分别可能返回什么异常？

   分别可能返回LeaderNotReadyException和LeaderSteppingDownException
   如果重试缓存中已经有正常完成的相同请求，Leader 尚未 ready 时可能直接返回缓存结果：

4. 非 Leader 为什么不能先追加本地日志再回复 Client？

   Client 写请求必须由 Leader 建立唯一的日志顺序，并分配相应的 term/index。Follower 只能通过 Leader 发出的 AppendEntries 接收日志。
   如果 Follower 可以直接把 Client 请求追加到自己的日志，不同节点就可能为同一个 index 生成不同内容，
   形成无法经过 Leader 协调和多数派确认的分叉日志，破坏 Raft 的日志一致性。因此非 Leader 必须尽早返回，不能执行 startTransaction() 和本地日志追加

5. 将它与 Day 4 Client 重试连接起来：

```text
Client 发错节点
  -> Server#checkLeaderState() 发现当前节点不是 Leader
  -> Server 返回携带 NotLeaderException 的 RaftClientReply
  -> Client#handleNotLeaderException() 读取 suggestedLeader 和 peers
  -> Client 更新 leaderId 以及自己保存的节点信息
  -> Client 重新选择目标节点
  -> 重试同一个逻辑请求
```

## 2.1 startTransaction 与 applyTransaction

1. `startTransaction()` 的输入、输出和职责分别是什么？

   * 输入为RaftClientRequest对象
   * 输出为TransactionContext对象
   * startTransaction() 接收 RaftClientRequest，对请求进行轻量级校验和解析，把 Client 请求及准备写入日志的状态机数据包装成 TransactionContext。这个上下文会继续参与日志构造、追加、提交和状态机应用，但此时还没有修改业务状态。

2. `context.getException()` 不为空时是否还会 append？

   不会进入 appendTransaction()。Ratis 将 context 中的异常包装成 StateMachineException，构造携带该异常的 RaftClientReply，取消当前事务并结束处理

3. 为什么 `startTransaction()` 不能理解成业务状态已经修改？

   startTransaction() 只负责校验、解析请求并准备 TransactionContext，此时日志还没有完成多数派复制和提交，也没有调用状态机的 applyTransaction()。只有日志提交以后，Ratis 调用 applyTransaction()，Arithmetic 才会真正修改 variables。

4. 对照填写：

| 方法 | 发生在 commit 前/后 | 主要职责                                | 是否直接代表业务完成            |
| --- |----------------|-------------------------------------|-----------------------|
| `startTransaction` | 前              | 开启ratis事务，生成TransactionContext上下文对象 | 否                     |
| `applyTransactionSerial` | 后              | 按日志提交顺序执行必要的轻量级串行准备工作                       | 否                     |
| `applyTransaction` | 后              | 应用raftLog                           | 是，但以返回的 Future 成功完成为准 |

## 2.2 Leader 本地追加与 PendingRequest

1. 在 `appendTransaction()` 中排列顺序：获取 permit、append local log、添加 pending、通知 sender。

   *  L886 final PendingRequests.Permit permit = leaderState == unsyncedLeaderState ? unsyncedPermit
     \: leaderState.tryAcquirePendingRequest(request.getMessage()); 
   * L895 state.appendLog(context); 
   * L908 pending = leaderState.addPendingRequest(permit, request, context);
   * L913 leaderState.notifySenders();
2. pending permit 为什么在 append 前尝试获取？
   permit 用于提前为 PendingRequest 预留请求数量和内存字节额度，实现服务端背压。如果已经超过 pending 请求数量或总字节数限制，应当在追加日志之前拒绝请求。
2. 否则日志已经追加成功后才发现无法保存 PendingRequest，就无法可靠地跟踪该日志对应的 Client Future 和最终回复。

3. `notifySenders()` 是否亲自发送网络请求？

   notifySenders() 不亲自构造或发送 RPC，只负责通知每个面向 Follower 的 LogAppender 有新日志可以处理。实际的日志读取、AppendEntries 请求构造和
   网络发送由相应的 LogAppender 实现负责。在当前使用 gRPC 的环境中，具体实现通常是 GrpcLogAppender。

4. PendingRequest 保存什么？为什么使用 TermIndex 关联？
   PendingRequest 保存原始 RaftClientRequest、对应的 TransactionContext、日志的 TermIndex，以及等待完成的 Client Reply Future。
   它表示一个已经进入日志处理流程、但尚未得到最终状态机结果的 Client 请求。
   使用 TermIndex 是为了把特定任期中的特定日志条目与 Client 请求精确关联；日志 commit/apply 后，可以根据相同的 TermIndex 找到并完成对应的 Future。


5. Leader 本地 append 后为什么不能立即成功回复 Client？
   Leader 本地 append
   ≠ 多数派复制完成
   ≠ 日志已经 commit
   ≠ 状态机已经 apply

### term=4、index=18 场景

假设该日志已经写入 Leader，但 Follower 尚未确认：

| 问题 | 我的判断 | 原因                                             |
| --- |------|------------------------------------------------|
| Leader 本地 RaftLog 是否可能已有 index 18 | 是    | 写入Leader了，即写入Leader的本地RaftLog                  |
| 多数派是否已经拥有 index 18 | 否    | Follower发送ACK到Leader本身就存在逻辑的滞后性                |
| commitIndex 是否必然为 18 | 否    | Leader 尚未获得足够的复制确认，不能仅凭本地 append 推断 commitIndex 已推进                 |
| Arithmetic `variables` 是否已修改 | 否    | 没有收到多数派的确认，就没有commit，就不会apply，因而variables不会被修改 |
| Client Future 是否应成功完成 | 否    | 此时leader并不会给Client返回成功完成的响应                    |

## 3.1 Leader 到 Follower 的复制链

1. 三节点 Leader 为什么通常有两个 LogAppender？

   因为LogAppender主要用来Leader用来向Follower发送AppendEntries() RPC请求，每个LogAppender对应一个Follower，三节点中，
   其角色分别为Leader/Follower/Follower，故Leader通常持有两个LogAppender

2. 一个 LogAppender 面向一个 Follower，还是面向所有 Follower？

   一个LogAppender面向一个Follower

3. `newAppendEntriesRequest()`、`ServerRpc.appendEntries()`、reply handler 各自负责什么？

   * newAppendEntriesRequest()负责从Leader日志准备发给特定Follower的AppendEntries
   * ServerRpc.appendEntries()负责发出server-server RPC
   * reply handler，reply handler 解析 Follower 返回的 AppendEntriesReplyProto。成功时更新该 Follower 的 matchIndex/nextIndex 并通知 LeaderState；日志不一致时调整 nextIndex 以便回退重试；发现更高 term 时通知 Leader 执行相应的退位处理。

4. `matchIndex` 表示什么？

   matchIndex表示Follower与leader日志完全匹配的最后一条logEntry的index，它与Leader自己的最后日志index不一定相等

补全复制链：

```text
Leader LogAppender
  -> 根据 Follower.nextIndex 从 Leader RaftLog 读取待复制日志
  -> newAppendEntriesRequest() 构造 AppendEntriesRequestProto
  -> ServerRpc#appendEntries() 发送 Server-to-Server RPC
  -> Follower RaftServerProxy#appendEntriesAsync
  -> 根据 groupId 找到对应的 RaftServerImpl
  -> Follower RaftServerImpl#appendEntriesAsync
  -> 检查 term 和 previousLog 是否匹配
  -> Follower RaftLog#append(entries)
  -> Follower 返回 AppendEntriesReplyProto
  -> Leader 的 reply handler 处理结果
  -> 成功时更新对应 FollowerInfo.matchIndex/nextIndex
  -> 通知 LeaderState 重新计算多数派位置
```

## 3.2 多数派

假设：

```text
n0（Leader）= 25
n1            = 25
n2            = 19
```

1. 多数派位置可能是多少？为什么不必限制在 19？

   多数派位置可能是 25。三节点集群的多数派是两个节点，n0 和 n1 都已匹配到 index 25，因此 index 25 已达到多数派复制条件。n2 暂时只到 19 不影响多数派成立，它可以随后继续追赶。

2. 如果 n1 也宕机，只剩 n0，为什么新的普通写入不能提交？

   因为当n1 n2宕机后，三节点集群的多数派为2，而此时已无法满足，所以后续写入不能再提交

3. Follower 收到日志是否等于它已经 apply？

   并不能，Follower收到日志只是第一步，它要根据leader appendEntries中携带的commitIndex更新自己的commitIndex，而后stateMachineUpdater被唤醒后将对应commitIndex之前的日志apply

## 4.1 commitIndex 推进

1. Leader 自己的复制位置和 Follower 的复制位置分别从哪里取得？

   * Leader自己的复制位置在RaftLog.getFlushIndex()中获取，最终由SegmentedRaftLogWorker进行维护
   * Follower的复制位置通过FollowerInfo.getMatchIndex()获取，由Follower返回的ack中携带，由LogAppender负责更新
2. `updateCommit(long majority, long min)` 在什么条件下推进 commitIndex？
   当 majority 大于旧的 commitIndex 时，Leader 尝试推进提交位置。实际候选位置是 min(majority, leaderFlushIndex)，确保 Leader 本地日志已经持久化。
   对于 Leader，该候选位置上的日志还必须属于 currentTerm；满足条件后 commitIndex 才会单调推进到该位置。参数 min 不直接决定 commitIndex，它用于更新 ReplicationLevel.ALL 的等待条件。

3. 为什么提交规则还接收 `currentTerm` 和 `isLeader`？

   currentTerm 和 isLeader 用于区分 Leader 与 Follower 的提交规则。Leader 根据多数派复制位置推进 commitIndex 时，候选位置的日志必须属于当前 term，以满足 Raft §5.4.2；提交当前任期日志时，
   它之前的旧任期日志会一并提交。Follower 不自行计算多数派，而是根据 Leader 传来的 commitIndex 推进，因此不执行相同的当前 term 限制。

4. `majority` 与 `min` 分别表达什么？
   majority 表示至少多数派成员已经达到的复制位置，Leader 用它作为候选 commitIndex，但仍需检查本地 flush 和当前 term。min 表示配置内所有参与成员复制位置的最小值，即“所有节点都达到的位置”，
   主要用于完成 ReplicationLevel.ALL 的等待请求，不直接用于推进普通的 commitIndex。

5. commitIndex 从 17 推进到 20，18～20 是什么状态？
    18-20都是committed状态，commitIndex表示的是该index(包含)之前的index都已经是committed状态

## 4.2 Follower 获知 commitIndex

1. Follower 本地已有 index 20，但收到的 Leader commitIndex 为 19，它能否自行提交 20？

   不可以，它必须要按照Leader commitIndex进行apply

2. Leader 通过什么请求把新的 commitIndex 告诉 Follower？没有新业务日志时能否通知？

   Leader通过appendEntries RPC将新的commitIndex告诉Follower，没有新业务日志时也要通知，只不过此时appendEntries中没有携带任何日志信息，降级为heartbeat

## 5.1 committed 与 applied

| 状态 | 我的解释                                                              |
| --- |-------------------------------------------------------------------|
| `lastLogIndex=12, commitIndex=10, appliedIndex=10` | 本地raftLog中最新日志的index为12，已经committed的raftLog的index为10，并且已经apply完毕  |
| `lastLogIndex=12, commitIndex=12, appliedIndex=10` | 本地raftLog中最新日志的index为12，已经committed的raftLog的index为12，11 12还未apply |
| `lastLogIndex=12, commitIndex=12, appliedIndex=12` | 本地raftLog中最新日志的index为12，已经committed的raftLog的index为12，并且已经apply完毕 |

1. `StateMachineUpdater` 为什么从 `appliedIndex + 1` 开始，并且只处理 committed 日志？
   appliedIndex 表示 StateMachineUpdater 已经处理到的最后日志位置，因此下一条从 appliedIndex + 1 开始，可以避免重复和遗漏。Updater 只处理不超过 commitIndex 的日志，
   因为 committed 才表示日志已经得到 Raft 共识；未提交日志仍可能被覆盖，不能提前修改业务状态。

2. Arithmetic 的业务变量在哪个类和方法中修改？

   在ArithmeticStateMachine的applyTransaction方法中修改

3. 状态机 Future 正常或异常完成后，`replyPendingRequest()` 分别怎样构造 reply？

状态机 Future 正常完成时，Ratis 构造 success=true、携带状态机结果 Message 和日志 index 的 RaftClientReply。
异常完成时，将原异常包装成 StateMachineException 并设置到 reply。
然后以 TermIndex 找到对应 PendingRequest，完成其 Future，并更新 RetryCache。

4. `commitIndex=10`、`appliedIndex=8` 表示什么？

   表示已经committed的raftLog的index为10，但是StateMachineUpdater应用到stateMachine中的index为8

## 5.2 三条异步链

### A. Client 请求进入与 Leader 本地追加

```text
RaftServerProxy#submitClientRequestAsync
  -> RaftServerImpl#submitClientRequestAsync
  -> RaftServerImpl#submitClientRequestAsyncInternal
  -> RaftServerImpl#replyFuture
  -> RaftServerImpl#writeAsync
  -> RaftServerImpl#writeAsyncImpl
       -> checkLeaderState
       -> retryCache.queryCache
       -> StateMachine#startTransaction
  -> RaftServerImpl#appendTransaction
       -> 获取 PendingRequest permit
  -> ServerState#appendLog
  -> RaftLogBase#appendImpl
       -> 生成 term/index
  -> SegmentedRaftLog#appendEntryImpl
  -> LeaderStateImpl#addPendingRequest
  -> 返回 PendingRequest Future
```

### B. Leader 复制与 commit 推进

```text
RaftServerImpl#appendTransaction
  -> LeaderStateImpl#addPendingRequest
  -> LeaderStateImpl#notifySenders
  -> GrpcLogAppender#appendLog
  -> GrpcLogAppender#sendRequest
  -> Follower 处理 AppendEntries
  -> AppendLogResponseHandler#onNext
  -> onNextImpl
  -> 更新 FollowerInfo.matchIndex
  -> LeaderStateImpl#onFollowerSuccessAppendEntries
  -> LeaderStateImpl#updateCommit
  -> ServerState#updateCommitIndex
  -> RaftLogBase#updateCommitIndex
```

### C. StateMachine apply 与 reply
    
```text
StateMachineUpdater#run
  -> StateMachineUpdater#applyLog
  -> RaftServerImpl#applyLogToStateMachine
  -> StateMachine#applyTransactionSerial
  -> StateMachine#applyTransaction
  -> ArithmeticStateMachine#applyTransaction
       -> assignment.evaluate(variables)
       -> 返回 CompletableFuture<Message>
  -> RaftServerImpl#replyPendingRequest
       -> 在状态机 Future 上注册 whenComplete
       -> 正常时构造 success reply
       -> 异常时包装 StateMachineException
  -> LeaderStateImpl#replyPendingRequest
       -> 根据 TermIndex 移除 PendingRequest
       -> 更新 RetryCache
       -> pending.setReply(reply)
       -> 完成 Client 等待的 Future
  -> GrpcClientProtocolService 中先前注册的回调被触发
  -> 将 RaftClientReply 发回 Client
```

为什么不能把三条链理解成同一线程中的连续同步调用栈？用什么字段关联事件？
三条链分别由 Client 请求处理、LogAppender/gRPC 回调和 StateMachineUpdater 驱动，通过事件、commitIndex 通知和 CompletableFuture 连接，而不是同一线程中的连续调用栈。
调试时使用 clientId+callId 关联原始 Client 请求和重试，使用 term+index 关联日志追加、复制、提交、状态机应用和 PendingRequest。TransactionContext 可用于辅助观察 Leader 内部的事务传递。

## 6.1 测试与断点证据

### Debug 配置

- 配置名称：days5-write-path
- JRE：11
- Module/classpath：ratis-examples
- Test kind 与测试类/方法：class org.apache.ratis.examples.arithmetic.TestArithmetic

### 第一轮：Leader 检查与本地 append

- 测试/线程：s1-client-thread2
- memberId：s1@group-0C6BFC5B0429
- clientId/callId：client-000000000001/23
- `checkLeaderState()` 返回值：null
- `initLogEntry` 的 term/nextIndex：1/1
- 最终 LogEntry term/index：1/1
- 我的结论：当前写请求 client-000000000001/23 在线程 s1-client-thread2 中由节点 s1 处理。checkLeaderState() 返回 null，说明该节点通过了 Leader、Leader ready 和
   非 stepping-down 检查。请求随后进入 appendTransaction() 和 state.appendLog(context)。在 RaftLogBase#appendImpl() 中，Leader 当前 term 为 1，getNextIndex() 得到 1，
  调用 operation.initLogEntry(1, 1) 后生成最终 LogEntryProto(term=1,index=1)。因此请求刚进入 Server 时没有日志 term/index，它们是在本地日志追加阶段构造的。

### 第二轮：Leader 到 Follower 复制与 commit

#### 2A. 本轮实现与断点

- 当前参数轮次（Simulated/gRPC/Netty）：Netty（本次选取输出中的 s6～s8 样本）
- 当前节点范围（例如 s0～s2）：s6～s8
- LogAppender 实际实现类（Default/Grpc）：LogAppenderDefault
- 实际命中的发送方法：LogAppenderDefault.sendAppendEntriesWithRetries()
- 实际命中的 reply handler：LogAppenderDefault.handleReply()

断点表达式作用域备忘：

```text
LogAppenderDefault 没有 getMemberId()。
Leader 完整成员标识：getServer().getMemberId()，例如 s1@group-XXXX
Leader 节点 ID：getServer().getId()，例如 s1
Follower 节点 ID：getFollowerId()
getFollowerId() 由 LogAppender 接口提供，等价于 getFollower().getId()。
```

`RaftServerImpl` 的断点中可以直接使用 `getMemberId()`；不要把两个类的表达式作用域混在一起。

#### 2B. Leader 构造并发送 AppendEntries

- 发送线程：本次 Tracepoint 表达式没有打印线程名，无法从现有输出确认
- Leader `getServer().getMemberId()`：s6@group-FF5E7A9FC8A9
- Leader `getServer().getId()`（仅 peerId）：s6
- 目标 `getFollowerId()`（等价于 `getFollower().getId()`）：s7（同一条日志也发送给了 s8）
- AppendEntries RPC callId：549（发送给 s7）；550（发送给 s8）
- previous term/index：1/68
- entries 数量：1
- 是否为 heartbeat（entries 是否为空）：否；entries=1，是携带日志的 AppendEntries
- 第一条 entry term/index：1/69
- 最后一条 entry term/index：1/69（本次只有一条 entry）
- `leaderCommit`：67

#### 2C. Follower 接收（可选断点）

- Follower 端 `RaftServerImpl#getMemberId()`：本次未设置 Follower 接收端 Tracepoint，未直接记录；发送目标分别为 s7、s8
- 是否与发送端 `getFollowerId()` 一致：从 SEND 的 replyId 与后续 REPLY follower 可以确认一致，分别是 s7、s8
- 收到的目标日志 term/index：1/69
- 收到的 `leaderCommit`：67
- 此时能否直接证明已经 apply，为什么：不能。AppendEntries 被接收或复制成功只证明日志进入 Follower 的 Raft 日志；状态机 apply 还要等待该日志 committed。输出中后续的 `FOLLOWER:s7-69`、`FOLLOWER:s8-69` 才能证明它们后来执行了 apply。

#### 2D. Leader 处理 AppendEntriesReply

- reply result：SUCCESS（s7、s8 均成功）
- reply term：当前 REPLY Tracepoint 没有打印该字段；不能从现有 REPLY 行直接填写
- reply followerCommit：当前 REPLY Tracepoint 没有打印该字段
- reply matchIndex/nextIndex：69/70
- `FollowerInfo.matchIndex` 更新前/后：68 -> 69（由上一条 index=68 的成功回复及本次成功分支更新结果关联得到）
- `FollowerInfo.nextIndex` 更新前/后：69 -> 70
- 本次是否调用 `onFollowerSuccessAppendEntries()`：是。SUCCESS 且 reply.nextIndex=70 大于更新前的 nextIndex=69，进入成功分支并调用该方法。

#### 2E. 多数派与 commitIndex

- majority/min：69/68
- Leader `flushIndex`：69
- currentTerm：1
- commitIndex 更新前/后：68 -> 69。第一次 COMMIT 输出为 `majority=69, oldCommitIndex=68`；随后一次 COMMIT 已显示 `oldCommitIndex=69`，证明前一次调用完成了推进。
- 若未推进，候选位置的 term 是否等于 currentTerm：本次已经推进；目标日志 term=1，与 currentTerm=1 相等

#### 2F. 我的结论

- 一个 LogAppender 面向：一个固定的 Follower。Leader s6 分别为 s7、s8 维护各自的 LogAppender 和复制进度。
- AppendEntries reply 成功后发生了什么：Leader 使用 reply.nextIndex 更新该 Follower 的 matchIndex/nextIndex，并调用 `onFollowerSuccessAppendEntries()` 重新计算多数派位置；本样本中 matchIndex 更新到 69，最终 commitIndex 从 68 推进到 69。
- 为什么第三个节点落后也可能推进 commitIndex：三节点集群的多数派是 2。Leader 自己和任意一个 Follower 已拥有 index=69 就形成多数派，不必等待另一个 Follower；`majority=69, min=68` 正好说明多数派位置已到 69，而最低位置仍可停在 68。

### 第三轮：StateMachine apply 与 reply

- StateMachineUpdater 线程：
- committed/applied：
- apply 的 term/index：
- assignment：
- variables 执行前/后：
- invocationId：
- PendingRequest 查找使用的 term/index：
- reply success/exception/logIndex：
- 我的结论：

- 测试命令：
- Tests run/Failures/Errors：
- BUILD 结果：
- 未命中的断点：
- 断点图标状态：
- 实际命中的相邻方法：
- 未命中原因与静态源码证据：

## 最终六时刻表

| 时刻 | 代表类#方法 | 日志此时存在于哪里 | 能否成功回复 Client | 原因 |
| --- | --- | --- | --- | --- |
| 收到请求 |  |  |  |  |
| Leader 校验通过 |  |  |  |  |
| Leader 本地追加 |  |  |  |  |
| 多数派复制 |  |  |  |  |
| commitIndex 推进 |  |  |  |  |
| 状态机 apply |  |  |  |  |

## 最终自测

1. 三节点为什么允许一台机器故障？

   **我的答案：**

2. Leader 本地 append 成功为什么还不能回复？

   **我的答案：**

3. 日志复制、日志提交、状态机应用为什么不是同一时刻？

   **我的答案：**

4. `RaftLog` 与 `ArithmeticStateMachine.variables` 各保存什么？

   **我的答案：**
