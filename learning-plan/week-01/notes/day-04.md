# Day 4 记录

## 同步链路

* client的声明类型是什么？

  Client的声明类型是RaftClient

* client的实际实现类是什么？

  client的实际类型为RaftClientImpl，具体代码在ClientImplUtils.newRaftClient()方法中

* io()返回的对象是什么类型？

  io()返回的对象类型为BlockingApi，实际类型为BlockingImpl

* send()的实现位于哪个类？

  位于BlockingImpl，最终调用client.getClientRpc.sendRequest(RatClientRequest)方法

* 哪个方法第一次调用了 `RaftClientRpc`？

  BlockingImpl.sendRequest(RaftClientRequest)方法第一次调用了RaftClientRpc

* 当前 `RaftClientRpc` 的实际实现为什么是 `GrpcClientRpc`？

  Assign继承自Client，在Client.run()方法中，设置了ClientRpc为new GrpcFactory().newRaftClientRpc()，即GrpcClientRpc对象

## 异步链路

> 填写方式：每完成一个小节，就把答案写在对应的“我的答案”下面。不要一次完成全部阶段。

### 4.1 异步入口和 Future

1. 外部 `client` 的声明类型与实际实现类型分别是什么？

   **我的答案：**Client的声明类型是RaftClient，实际类型为RaftClientImpl

2. `async()` 的声明返回类型与实际返回对象分别是什么？

   **我的答案：**声明类型为AsyncApi，实现类为AsyncImpl

3. `AsyncImpl` 内部的 `client` 是什么类型？与外部 `client` 是什么关系？

   **我的答案：**RaftClientImpl类型，跟外部client为同一个client

4. 为什么异步 `send()` 返回 `CompletableFuture<RaftClientReply>`？调用 `send()` 返回时，Server 是否必然处理完成？

   **我的答案：**异步 `send()` 通常不等待 RPC 最终响应，而是返回代表未来结果的 Future；但获取并发许可时仍可能阻塞。

5. `thenAccept(...)` 与 `join()` 分别怎样使用异步结果？哪里会发生等待？

   **我的答案：**thenAccept()` 注册一个结果处理动作，本身通常不会等待结果；`join()` 会主动等待结果并返回 `RaftClientReply`。

### 4.2 异步主调用链

1. 普通异步写请求使用哪一种 request type？最终进入 `OrderedAsync` 还是 `UnorderedAsync`？

   **我的答案（附源码位置）：**使用TypeCase = WRITE，ReplicationLevel.MAJORITY(AsyncApi:L46)，最终进入OrderedAsync(AsyncImpl:L43)

2. 异步请求的 `callId` 在哪里产生？`seqNum` 在哪里分配？

   **我的答案：**callId在OrderedAsync.send()方法中分配(OrderedAsync:L171)，seqNum在SlidingWindow.Client.submitNewRequest()方法中分配(SlidingWindow:L284)

3. `RaftClientRequest` 在哪里构建？哪个方法第一次调用 `RaftClientRpc`？

   **我的答案：**RaftClientRequest在OrderedAsync.send()方法中构建(L173)，重试时会再次构建 `RaftClientRequest`，但继续使用原来的 `callId` 和 `seqNum`。OrderedAsync.sendRequestWithRetry()方法第一次调用RaftClientRpc(L207)

4. 补全调用链，并在每一跳后写一句职责：

```text
RaftClientImpl#async // 构造AsyncImpl对象
  -> RaftClientImpl#getOrderedAsync
  -> AsyncImpl#send // 总的入口
  -> OrderedAsync#send // 核心业务逻辑入口
  -> SlidingWindow.Client#submitNewRequest // 构造滑动窗口，保证消息发送/重试的有序性
  -> OrderedAsync#sendRequestWithRetry // 加入重试逻辑
  -> GrpcClientRpc#sendRequestAsync // 对grpc的封装
```

**我的说明：**

### 4.3 PendingOrderedRequest 与 Future

1. `PendingOrderedRequest` 表示什么？为什么称为 pending？

   **我的答案：** 继承自PendingClientRequest，PendingClientRequest对requestConstructor以及其异步结果的封装，PendingOrderedRequest在此基础上加入了有序性，即封装了滑动窗口的序号，因为表示正在发送的对象，所以使用pending

2. 它保存了哪些关键状态？

   * 继承自PendingClientRequest中的RaftClientRequest，表示请求对象，以及replyFuture，表示异步结果
   * 自身额外封装的状态
     * callId，在本次gRPC中的唯一标识
     * seqNum，滑动窗口的序号信息
     * requestConstructor，requestConstructor，用来构造RaftClientRequest对象
     * isFirst，用来标识是否为第一个请求

3. `OrderedAsync#send()` 返回的 Future 来自哪里？回复怎样完成正确请求的 Future？

   **我的答案：** Future来自PendingClientRequest默认构造的replyFuture，该future通过调用PendingOrderedRequest.setReply()方法完成正确请求

4. 发送顺序为 `1 → 2 → 3`、回复顺序为 `3 → 1 → 2` 时，会不会串错 Future？为什么？

   **我的答案：** 不会，Client 滑动窗口也能根据 `seqNum` 找到正确 Future。

### 4.4 callId、seqNum 与有序异步

| 对比项 | `callId` | `seqNum` |
| --- | --- | --- |
| 在哪里产生 | OrderedAsync.send() | SlidingWindow.Client.submitNewRequest() |
| 主要用途 | 标识请求在gRPC中的唯一性 | 标识请求在滑动窗口中的序号 |
| 是否属于滑动窗口 | 否 | 是 |
| 重试时是否改变 | 否                       | 否 |
| 是否用于表达窗口内顺序 | 否 | 是 |

1. 已经有 `callId`，为什么还需要 `seqNum`？

   **我的答案：**`clientId + callId` 标识一次 Ratis 客户端逻辑请求；重试时保持不变，方便 Server 的 retry cache 判断这是同一个请求的重试。客户端为请求分配顺序；Server 即使乱序收到，也依据 `seqNum` 缓存并按连续顺序处理和回复。

2. “有序异步”是否意味着必须等前一个请求完成后才能发送下一个？多个请求能否同时在途？

   **我的答案：**不是，有序异步只是客户端侧在发送时，要按序发送，服务端处理时要按序处理，并不代表着前一个请求完成后才能发送下一个，由OUTSTANDING_REQUESTS_MAX_DEFAULT决定，默认为100个

3. “有序”主要保证什么？

   **我的答案：**客户端有序发送请求，服务端有序处理请求，并有序发送给客户端

### 4.5 SlidingWindow 指定位置

1. `nextSeqNum` 初始值是什么？新请求提交时怎样变化？

   **我的答案：**初始值为1，提交时自增1

2. `requests`、`delayedRequests`、`firstSeqNum` 分别表示什么？

   * requests中的元素有两层含义
     * 一是用来表示还没有收到回复的请求列表
     * 二是已经收到了回复，但是其前序还存在没有回复的请求，也会被保留在requests中

   * delayedRequests用来表示待发送的请求
   * 当前滑动窗口中第一个实际提交请求的序号。

3. 为什么请求需要 `isFirst`？`receiveReply()` 为什么要处理乱序回复？

   * isFirst有两层含义
     * 一是同来进行leader探测，client在第一次发送请求时，并不一定知道leader的确切位置，那么需要先发送一个请求进行试探，待收到处理成功的回复后，可以批量发送后续请求。这个逻辑可以确保网络上没有过多无效流量
     * 告诉 Server：“这是当前滑动窗口的起点，你可以从这个 seqNum 初始化 `nextToProcess`。”

4. 回复先到是否等于业务请求可以越过前面的请求执行？

   **我的答案：**不可以

### 4.6 并发限制

1. `requestSemaphore.acquire()` 与 `release()` 分别在限制什么？

   **我的答案：**起始做的是一件事，现在异步发送的请求的数量

2. 并发额度用完后，下一次 `send()` 会发生什么？

   **我的答案：**在requestSemaphore.acquire()方法处阻塞，等待有请求收到响应后，调用release()方法

3. “异步 API 在任何情况下都不会阻塞调用线程”是否准确？

   **我的答案：**不准确，requestSemaphore.acquire()会阻塞调用线程

### 4.7 异步重试

1. RPC 异常在哪里进入重试处理？哪个对象决定是否重试和等待多久？

   **我的答案：**在OrderedAsync.sendRequestWithRetry()方法中，调用了handleException()方法，由RetryPolicy对象决定

2. `NotLeaderException` 出现后，客户端更新什么？为什么可能重置滑动窗口？

   * 更新 peer 配置；

   * 选择新的目标 Server；

   * 重置滑动窗口的 `firstSeqNum`。

   新 Leader 对旧客户端窗口的处理进度可能不了解，Client 需要重新标记一个 first request，让新 Server 建立窗口起点。

3. 重试时下面四项怎样变化？

| 状态 | 保持/增加/可能改变 | 原因 |
| --- | --- | --- |
| `callId` | 保持 | 这是每个请求的唯一标识，客户端可能异常重试，服务端可以区分这是通过callId确认这是重复请求 |
| `seqNum` | 保持 | 重试仍是同一窗口中的同一个有序请求，不能因为重试改变它在序列中的位置。 |
| `attemptCount` | 增加 | 重试次数，肯定是要增加的，用来指导RetryPolicy |
| target server | 可能改变 | 发生leader切换 |

4. 哪些情况下 Future 会以异常结束？

   RetryPolicy 决定不再重试；
   
   遇到不可重试异常；
   
   Client 已关闭；
   
   获取 semaphore 时线程被中断；
   
   整个窗口因严重异常被失败结束。

### 4.8 场景分析

```text
请求 1：x = 1
请求 2：x = x + 1
请求 3：读取 x
```

1. 三个请求能否都在请求 1 回复前提交？

   **我的答案：** 三个请求都可以在请求1回复前提交到客户端滑动窗口，但新窗口建立阶段通常只有第一个请求先实际发送到 Server。

2. RPC 回复能否乱序到达？请求 3 能否因为回复先到而越过请求 2 执行？

   **我的答案：** 状态机处理结果或底层事件可能乱序完成；Server 滑动窗口会尽量按序发送回复，Client 也通过 seqNum 将回复关联到正确 Future。请求3不能因为先完成就越过请求2成为对外有序结果。

3. 客户端有序窗口与 Raft Server 的日志顺序分别负责什么？

   **我的答案：** 客户端滑动窗口负责同一 Client 的有序请求提交、重试和 Future 匹配；Raft 日志顺序负责集群范围内日志的一致顺序、复制、提交和状态机应用。Follower 可以暂时落后，并不要求任何时刻日志位置都完全相同。


## RaftClientRequest 关键字段

| 字段 | 来源 | 本次观察值/说明 |
| --- | --- | --- |
| clientId | RaftClient.Builder.build()方法生成的随机值 | client-000000000001 |
| groupId | 客户端指定，SubCommand中的raftGroupId默认值或者由--raftGroup指定 | group-C6576C97241B |
| callId | 在BlockingImpl.send()方法中，由CallId.getAndIncrement()静态方法生成 | 23 |
| serverId/leaderId | `RaftClientImpl` 初始化时通过 `computeLeaderId()` 选择初始目标；构造请求时，`RaftClientImpl#newRaftClientRequest()` 使用显式 server，或者当前 `leaderId` | s0 |
| message | 由client侧实现AssignmentMessage，实现Message接口 | a = 3 |
| type | BlockingImpl.send(Message)方法中RaftClientRequest.writeRequestType() | RW |

* message最早来自 Arithmetic 业务代码，不是 Builder 自己生成的。

* serverId是客户端当前认为的 Leader，不保证第一次一定正确。

* callId表示逻辑请求，不等于重试次数；同一请求重试时通常保持 callId，而 `attemptCount` 增加。

## Leader 选择与重试

```text
初始目标选择：
 - 1. 若客户端指定，使用客户端指定的leaderID
 - 2. 尝试从客户端缓存中查找
 - 3. 在peers中查找优先级最高的peer，作为leaderID

NotLeaderException：
目标 Server 收到请求后，通过 checkLeaderState(...) 检查自己是否为 Leader。
如果不是 Leader，则返回包含自身记录的leaderID、raftPeers等信息的 NotLeaderException。判断规则为
 - 1. 若本节点不是running状态
 - 2. 若本节点记录的leaderID不是自身
leaderId 更新：
Client 收到 NotLeaderException 后，调用handleIOException()。
如果异常中存在 suggestedLeader，则把 leaderId 更新为suggestedLeader；
同时还可能根据服务端返回的newPeers更新客户端保存的 peers。
RetryPolicy 决定：
一次请求失败后，BlockingImpl 把失败信息交给RetryPolicy。
它返回一个 RetryAction，决定：

1. 是否继续重试：raction.shouldRetry()；
2. 重试前等待多久：client.getEffectiveSleepTime；
3. 不再重试时，最终怎样结束：throw client.noMoreRetries。

重试仍然属于同一个逻辑请求，因此 callId不变，
但每次重新构建请求时 attemptCount自增，
目标 Server可能发生改变。
```

## 同步与异步对照

| 对比项 | `io().send()` | `async().send()` |
| --- | --- | --- |
| 返回类型 | RaftClientRequest | CompletableFuture\<RaftClientReply> |
| 主要实现 | BlockingImpl.send(Type, Message, RaftPeerId) | AsyncImpl.sned(Type, Message, RaftPeerId) |
| RPC 方法 | client.getClientRpc().sendRequest(request) | client.getOrderedAsync(server).send(type, message, server) |
| 调用线程是否等待 | 是 | 可能等待 |

### 为什么 OrderedAsync 需要序号和 pending 队列

​	序号是用来保证客户端将请求按序发送给服务端，服务端将响应按序返回给客户端

​	pending队列用来缓存已发送但是还未收到响应的请求，同时可以用来给请求打上序号

​	pending队列用来缓存已发送但是还未收到响应的

## 断点观察

- 线程名：main
- callId：34625
- target peer：null

