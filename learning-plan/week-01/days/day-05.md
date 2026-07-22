# Day 5：一条写请求在 Server 中经历了什么

## 今天为什么重新设计

Day 4 停在：

```text
GrpcClientRpc 把 RaftClientRequest 发给目标 RaftServer
```

今天从请求到达 Server 开始，只跟一条写请求的六个时刻：

```text
接收 -> Leader 校验 -> 本地追加 -> 复制 -> 提交 -> 状态机应用/回复
```

原手册一次要求阅读 `RaftServerImpl`、`LeaderStateImpl`、`LogAppender`、`RaftLog`、`StateMachineUpdater`，范围太大。新手册每个阶段只回答一个问题，不要求读完整个类。

预计用时：4～5 小时，建议分两次完成。

所有答案填写到 `notes/day-05.md`。记录文件已按 `0.1～6.3` 预留答案区；每完成一个
小节就停下来填写，不要先通读全部类再凭记忆作答。

## 完成后你应当能回答

1. Client 请求通过哪个入口进入对应的 `RaftServerImpl`？
2. 非 Leader 为什么在创建事务和追加日志前返回？
3. `startTransaction`、append、replicate、commit、apply 分别发生了什么？
4. `PendingRequest` 为什么在本地追加时建立、在状态机结果完成后结束？
5. 三节点为什么复制到 Leader 加一个 Follower 就可能推进 commitIndex？
6. `commitIndex` 与 `lastAppliedIndex` 为什么允许暂时不同？

---

## 今天最重要的边界

在开始前，先把下面五句话抄入 `notes/day-05.md`，实验后逐条校正：

```text
1. 收到请求，不等于写入日志。
2. 写入 Leader 本地日志，不等于复制到多数派。
3. 复制到多数派，不等于每台机器都已经复制。
4. 日志提交，不等于状态机此前已经执行。
5. 状态机执行完成，才产生本例的业务结果并完成 Client reply。
```

---

# 阶段零：先认识六个角色

| 角色 | 今天只关注什么 |
| --- | --- |
| `RaftServerProxy` | 根据 groupId 把 RPC 请求交给对应 Division |
| `RaftServerImpl` | 处理该 RaftGroup 的请求和角色判断 |
| `LeaderStateImpl` | Leader 专属状态、Follower 复制进度、pending request、commit 推进 |
| `RaftLog` | 保存按 term/index 排列的复制日志 |
| `LogAppender` | Leader 向某一个 Follower 发送 AppendEntries |
| `StateMachineUpdater` | 依次取出 committed 但未 applied 的日志并交给状态机 |

先画容器关系，不画方法：

```text
RaftServerProxy
  -> RaftServerImpl (一个 group/division)
       +-- ServerState
       |    +-- RaftLog
       +-- LeaderStateImpl（仅 Leader 角色存在）
       |    +-- LogAppender -> Follower n1
       |    +-- LogAppender -> Follower n2
       |    +-- PendingRequests
       +-- StateMachineUpdater
            +-- ArithmeticStateMachine
```

## 0.1 不要把“包含关系”和“调用关系”混在一起

上图只回答“谁持有谁/谁服务于谁”，还不是一次请求的调用栈。先在笔记中填写角色表：

| 角色 | 是入口、协调者、日志、复制器还是状态机执行器 | 它不负责什么 |
| --- | --- | --- |
| `RaftServerProxy` | 入口 | 不负责处理具体写事务，也不负责追加和提交日志 |
| `RaftServerImpl` | 入口 | 不亲自维护每个 Follower 的复制循环，也不直接保存 Arithmetic 变量 |
| `LeaderStateImpl` | 协调者 | Follower 复制进度和 commit 推进不负责持久化日志内容，也不直接执行 Arithmetic 表达式 |
| `RaftLog` | 日志 | 不负责修改 `ArithmeticStateMachine.variables`，也不负责发送 RPC |
| `LogAppender` | 复制器 | 不独自决定整个集群是否形成多数派，也不负责状态机 apply |
| `StateMachineUpdater` | 状态机执行器 | 给状态机不负责选举 Leader、接收 Client 请求或向 Follower 复制日志 |

例如：`RaftLog` 负责保存复制日志，但它不会直接修改 Arithmetic 的 `variables`。

### 阶段零检查点

1. `RaftServerImpl` 与 `LeaderStateImpl` 是不是同一个对象？

   不是。`RaftServerImpl` 表示一个 Raft Group/Division 的 Server 实现，无论当前是 Leader、Follower 还是 Candidate 都存在。`LeaderStateImpl` 是节点成为 Leader 后才具有的 Leader 专属状态，由 `RaftServerImpl` 的角色状态间接持有和使用

2. 三节点 Leader 为什么通常有两个面向 Follower 的 LogAppender？

   因为LogAppender主要用来Leader用来向Follower发送AppendEntries() RPC请求，每个LogAppender对应一个Follower，三节点中，其角色分别为Leader/Follower/Follower，故Leader通常持有两个LogAppender

3. `StateMachineUpdater` 处理的是未提交日志还是已提交日志？

   已提交的日志，即committed的日志

4. `RaftLog` 与 `ArithmeticStateMachine.variables` 保存的是不是同一种数据？

   不是。`RaftLog` 保存可复制的 Raft 日志条目，关注 term、index、Client 请求和提交状态；`variables` 保存已经 apply 后的 Arithmetic 业务状态，例如变量 `a=3`。日志是共识记录，variables 是执行日志后得到的业务结果

   

---

# 阶段一：请求进入 Server，但先判断“我是不是 Leader”

## 1.1 只跟接收入口

按顺序定位：

```text
RaftServerProxy#submitClientRequestAsync
  -> RaftServerImpl#submitClientRequestAsync
  -> RaftServerImpl#submitClientRequestAsyncInternal
  -> RaftServerImpl#replyFuture
  -> RaftServerImpl#writeAsync
  -> RaftServerImpl#writeAsyncImpl
```

每个方法只写一句职责，不展开 read、watch、message stream 等其他分支。

在 `replyFuture()` 中确认 `WRITE` 进入 `writeAsync()`。

把入口拆成两个边界理解：

```text
RaftServerProxy：根据 groupId 找到 Division
RaftServerImpl：在该 Division 内处理具体 ClientRequest
```

回答：

1. 为什么一个 Server 进程还需要 `RaftServerProxy`，不能让所有请求直接进入同一个
   `RaftServerImpl`？
2. `replyFuture()` 根据哪个字段选择 `WRITE` 分支？
3. 此时只是“收到请求”，还是已经产生了日志 term/index？请给源码证据。

## 1.2 找到非 Leader 分支

在 `writeAsyncImpl()` 开头找到：

```java
checkLeaderState(request)
```

回答：

1. 当前节点不是 Leader 时，是否继续调用 `stateMachine.startTransaction()`？
2. 返回的 reply 中是什么异常类型？
3. `NotLeaderException` 中为什么要包含 suggestedLeader 和 peers？
4. `checkLeaderState()` 返回 `null` 表示失败，还是表示 Leader 检查通过？不要凭通常的
   `null` 用法猜测，要看方法注释和调用方判断。
5. 除了 `NotLeaderException`，Leader 尚未 ready 或正在 step down 时分别可能返回什么异常？

把答案与 Day4 的 Client 重试链连接起来：

```text
Client 发错节点
  -> Server#checkLeaderState 返回 NotLeaderException
  -> Client#handleNotLeaderException 更新目标
  -> 重试同一个逻辑请求
```

### 阶段一检查点

非 Leader 为什么必须尽早返回，不能先追加本地日志再告诉 Client？

在笔记中补出链路，并给每一跳写一句职责：

```text
RaftServerProxy#submitClientRequestAsync
  -> RaftServerImpl#submitClientRequestAsync
  -> RaftServerImpl#submitClientRequestAsyncInternal
  -> RaftServerImpl#replyFuture
  -> RaftServerImpl#writeAsync
  -> RaftServerImpl#writeAsyncImpl
```

---

# 阶段二：Leader 把业务请求变成日志事务

## 2.1 `startTransaction` 此时还不是 apply

在 `RaftServerImpl#writeAsyncImpl` 找到：

```java
stateMachine.startTransaction(request)
```

这里容易误解。`startTransaction` 用于把 Client 请求准备成 `TransactionContext`，可做校验和构造状态机日志数据；它不是“执行已经提交的业务状态”。

对比两个方法：

```text
StateMachine#startTransaction    提交前准备事务
StateMachine#applyTransaction    提交后应用业务状态
```

回答：

1. `startTransaction()` 的输入是什么？输出的 `TransactionContext` 起什么作用？
2. 如果 `context.getException()` 不为空，代码还会进入 `appendTransaction()` 吗？
3. 为什么把“准备/校验事务”误认为“执行业务”会导致你错误判断请求已经成功？

## 2.2 Leader 本地追加

继续跟：

```text
RaftServerImpl#appendTransaction
  -> ServerState#appendLog
  -> RaftLog#append
```

在 `appendTransaction()` 中分别找到三件事：

1. `state.appendLog(context)`：把事务追加到 Leader 本地日志。
2. `leaderState.addPendingRequest(...)`：保留尚不能回复的 Client 请求。
3. `leaderState.notifySenders()`：通知复制线程有新日志可发。

再找出它们的准确先后顺序，并回答：

1. pending permit 为什么在真正 append 前先尝试获取？
2. `state.appendLog(context)` 之后，日志首先存在于哪一台机器？
3. `notifySenders()` 自己是否直接把日志发到网络？谁才负责面向 Follower 发送？

## 2.3 为什么已经 append 还要 pending

此时请求已经在 Leader 本地日志中，但尚未证明多数派复制成功，所以不能立即向 Client 宣称成功。

```text
PendingRequest = Client 正在等待的请求
               + 对应日志 term/index
               + 将来完成 reply 的 Future
```

### 阶段二检查点

1. `startTransaction()` 与 `applyTransaction()` 为什么不能合并？
2. `state.appendLog(context)` 返回后能否立刻成功回复 Client？
3. PendingRequests 为什么以 TermIndex 关联请求？
4. 如果两个 Client 请求几乎同时进入，为什么不能用“最近一个请求”来匹配回复？

## 2.4 用一个时间点练习校正概念

假设 `(term=4, index=18)` 已经由 `state.appendLog(context)` 写入 Leader，但两个
Follower 尚未确认。填写：

| 问题 | 此时答案 |
| --- | --- |
| Leader 本地 RaftLog 是否可能已有 index 18 |  |
| 多数派是否已经拥有 index 18 |  |
| commitIndex 是否必然为 18 |  |
| Arithmetic `variables` 是否已修改 |  |
| Client Future 是否应成功完成 |  |

---

# 阶段三：Leader 如何把日志复制给两个 Follower

## 3.1 一个 LogAppender 面向一个 Follower

只阅读下面两个类的类注释和主循环附近，不读全部辅助方法：

```text
LogAppenderBase
LogAppenderDefault
```

在 `LogAppenderDefault` 中定位：

```text
newAppendEntriesRequest(...)
getServerRpc().appendEntries(...)
handleReply(...)
```

写出它们分别负责：

| 方法/调用 | 职责 |
| --- | --- |
| `newAppendEntriesRequest` | 从 Leader 日志准备发给某 Follower 的 AppendEntries |
| `ServerRpc.appendEntries` | 发出 Server-to-Server RPC |
| `handleReply` | 更新该 Follower 的复制进度并通知 LeaderState |

回答：

1. 三节点集群的 Leader 通常为什么有两个 LogAppender？
2. `newAppendEntriesRequest(...)` 从哪里取得待复制日志？
3. LogAppender 维护的是全体 Follower 的一个总进度，还是某个 Follower 的进度？
4. `matchIndex` 可以怎样理解？它与 Leader 自己的最后日志 index 一定相等吗？

## 3.2 Follower 收到日志

回到 `RaftServerImpl`，定位：

```text
appendEntries/appendEntriesAsync
  -> RaftLog#append(entries)
```

观察 Follower reply 会携带它成功处理到的 index/结果。Leader 根据多个 Follower 的进度判断多数派位置。

只记录主干，不钻冲突回退细节：

```text
Leader LogAppender
  -> ServerRpc#appendEntries
  -> Follower RaftServerProxy#appendEntriesAsync
  -> Follower RaftServerImpl#appendEntriesAsync
  -> Follower RaftLog#append
  -> AppendEntriesReply
  -> Leader 更新对应 FollowerInfo
```

## 3.3 三节点多数派不是“三台全成功”

三节点的多数派数量为：

```text
floor(3 / 2) + 1 = 2
```

因此 Leader 自己加任意一个 Follower 成功复制即可形成多数派。另一个 Follower 可以暂时落后，之后再追赶。

### 阶段三检查点

1. 为什么三节点允许一台故障，但两台故障后不能继续提交新写入？
2. 日志复制到一个 Follower 后，第三台是否必须立即完成才能提交？
3. LogAppender 保存的是业务变量值，还是日志复制进度？
4. “Follower 收到 AppendEntries”与“Follower 已经 apply 该日志”是否等价？

### 3.4 多数派手算题

假设三台机器的已匹配位置为：

```text
n0（Leader）= 25
n1            = 25
n2            = 19
```

回答：多数派位置可能是多少？能否因为 n2 只有 19 就把提交位置限制为 19？如果 n1
也宕机，只剩 n0=25，新的普通写入为什么不能继续提交？

---

# 阶段四：从多数派位置推进 commitIndex

## 4.1 找到 Leader 的 commit 推进点

在 `LeaderStateImpl` 中搜索：

```text
updateCommit
majority
updateCommitIndex
```

跟到：

```text
LeaderStateImpl
  -> ServerState#updateCommitIndex
  -> RaftLogBase#updateCommitIndex
```

本周只理解两个输入：

- `majorityIndex`：根据各节点复制进度计算出的多数派位置；
- `currentTerm`：Raft 提交规则还要考虑任期，不能只机械地取中位数。

不要在第一周证明完整 Raft safety；先记录代码确实没有使用“所有节点最小 index”作为提交位置。

回答：

1. `getMajorityMin(...)` 的输入中，Leader 自己的位置来自哪里，Follower 的位置来自哪里？
2. `updateCommit(long majority, long min)` 在什么条件下尝试推进？
3. `ServerState#updateCommitIndex` 为什么还接收 `currentTerm` 与 `isLeader`？本周只回答
   “说明提交规则不只比较数字大小”，不要求证明完整安全性。
4. `majority` 与 `min` 分别服务于什么目的？不要把“多数派复制”误写成“所有节点复制”。

## 4.2 Leader 如何把 commitIndex 告诉 Follower

AppendEntries 不只携带新日志，也携带 Leader 的 commitIndex。Follower 在 `appendEntriesAsync(...)` 中计算有效 commitIndex 并调用：

```text
ServerState#updateCommitIndex(..., isLeader=false)
```

所以 Follower 即使没有新日志，也可以通过后续 heartbeat/AppendEntries 得知更高的 commitIndex。

### 阶段四检查点

1. “日志已经存在”与“commitIndex 已经越过该日志”有什么区别？
2. Follower 的日志已追加后，为什么可能要等下一次 Leader 通知才开始 apply？
3. Leader 使用的是所有节点确认位置，还是多数派确认位置？
4. commitIndex 从 17 推进到 20，是否表示 18～20 都进入 committed 范围？

### 4.3 commitIndex 传播场景

假设 Follower 已追加 index 20，但它收到的 AppendEntries 中 Leader commitIndex 仍为 19。
回答：它能否仅凭“本地已有 index 20”就自行把 20 视为 committed？后续哪类消息可以把
新的 Leader commitIndex 告诉它？

---

# 阶段五：StateMachineUpdater 只应用 committed 日志

## 5.1 比较两个游标

打开 `StateMachineUpdater`，只找：

```text
raftLog.getLastCommittedIndex()
getLastAppliedIndex()
applyLog(...)
```

核心循环可以抽象为：

```text
while appliedIndex < commitIndex:
    next = raftLog[appliedIndex + 1]
    apply next to state machine
appliedIndex++
```

填写三个状态：

| 状态 | 含义 |
| --- | --- |
| `lastLogIndex=12, commitIndex=10, appliedIndex=10` |  |
| `lastLogIndex=12, commitIndex=12, appliedIndex=10` |  |
| `lastLogIndex=12, commitIndex=12, appliedIndex=12` |  |

## 5.2 真正的业务执行位置

跟踪：

```text
StateMachineUpdater#applyLog
  -> RaftServerImpl#applyLogToStateMachine
  -> StateMachine#applyTransactionSerial
  -> StateMachine#applyTransaction
  -> ArithmeticStateMachine#applyTransaction
```

此时才修改 Arithmetic 的 `variables` 业务状态。

回答：

1. `StateMachineUpdater` 为什么从 `appliedIndex + 1` 开始？
2. 它为什么只循环到本次观察到的 `committed`？
3. `applyTransactionSerial()` 和返回 Future 的 `applyTransaction()` 为什么是两个步骤？
   本周只记录调用顺序，不展开状态机并发模型。
4. Arithmetic 的业务变量在哪个具体类和方法中被修改？

## 5.3 Client reply 在哪里完成

在 `RaftServerImpl#applyLogToStateMachine` 中继续观察：

```text
replyPendingRequest(...)
  -> LeaderStateImpl#replyPendingRequest
  -> 从 PendingRequests 移除
  -> 完成对应 Future
```

这解释了为什么 `BlockingImpl.send()` 会一直等待：它等待的 Server reply 与已经提交并应用的那条日志关联。

### 阶段五检查点

1. `commitIndex=10`、`appliedIndex=8` 表示什么？
2. Arithmetic 的 `variables.put(...)` 应发生在 append 前还是 commit 后？
3. Client reply 为什么要与 pending request 关联，而不能只按“最近一个请求”回复？
4. 状态机 Future 异常时，Server 如何把它包装进 `RaftClientReply`？

## 5.4 把三条异步链分开

不要画成一个能够连续 Step Into 的同步调用栈。在笔记中分别填写：

```text
A. Client 请求进入与 Leader 本地追加
B. Leader 向 Follower 复制并推进 commitIndex
C. StateMachineUpdater apply 并完成 pending reply
```

再回答：这三条链为什么可能运行在不同线程或通过 Future/事件连接？调试时应使用什么
字段把它们关联起来？至少写出 `callId`、term/index 中的两个。

---

# 阶段六：用 IntelliJ Debug 分三轮验证写链

这一阶段的目标不是一次单步走完整条链，而是用三次独立 Debug 分别取得以下证据：

```text
第一轮：Client 请求到达 Leader，并在 Leader 本地生成 term/index
第二轮：一个 LogAppender 把该日志复制给某个 Follower，Leader 更新 matchIndex/commitIndex
第三轮：StateMachineUpdater 应用 committed 日志，并完成 PendingRequest Future
```

这三段由不同线程、事件和 Future 驱动。第一轮结束后重新运行测试做第二轮是正常做法，不是调试失败。

## 6.0 Debug 前准备

### 第一步：先用命令行确认代码可以构建

在项目根目录 `D:\software\idea_workstation\ratis_20260610\ratis` 执行：

```powershell
.\mvnw.cmd -pl ratis-examples -am `
  "-DskipTests=false" `
  "-Dtest=TestArithmetic" `
  "-Dsurefire.failIfNoSpecifiedTests=false" `
  test
```

确认：

```text
Tests run: 6
Failures: 0
Errors: 0
BUILD SUCCESS
```

命令行失败时先解决构建问题，不要立即开始 IDE Debug。命令行成功但 IDEA 标红时，优先处理 Maven Reload、generated-sources 和索引问题。

### 第二步：创建固定的 JUnit Debug 配置

打开：

```text
Run -> Edit Configurations...
```

点击左上角 `+`，选择 `JUnit`，按下面填写：

| 配置项 | 填写值 |
| --- | --- |
| Name | `Day5-Write-Path` |
| Run on | `Local machine` |
| Java/JRE | 项目统一使用的 JDK 11 |
| Module / Use classpath of module | `ratis-examples` |
| Test kind | `Class` |
| Class | `org.apache.ratis.examples.arithmetic.TestArithmetic` |
| VM options | `-ea -Djunit.jupiter.execution.timeout.mode=disabled_on_debug` |
| Working directory | `$PROJECT_DIR$` |

如果你的 IDEA 使用新版界面：

1. `Build and run` 左侧的 JRE 下拉框选择项目 JDK 11（例如 `D:\software\jdk11`）。
2. 右侧 `-cp` classpath 下拉框选择 `ratis-examples`；测试类必须由这个模块的 test classpath 加载。
3. 测试种类下拉框选择 `Class`。
4. 在红框中输入完整测试类名。
5. 点击 `Apply`，再点击 `OK`。

`TestArithmetic` 间接继承的 `BaseTest` 带有 `@Timeout(100)`。正常运行时这个 100 秒保护很有用，但人工停在断点观察很容易超过 100 秒。上面的 `disabled_on_debug` 只在检测到 Debugger 时禁用 JUnit timeout，普通 Run 和 Maven 测试仍保留超时保护。

也可以把 Test kind 改成 `Method`，只运行：

```text
org.apache.ratis.examples.arithmetic.TestArithmetic#testGaussLegendre
```

这是参数化测试，运行时可能出现多组 invocation，属于正常现象。

### 第三步：认识四个常用 Debug 操作

| 操作 | 快捷键 | 本阶段用途 |
| --- | --- | --- |
| Resume Program | `F9` | 放行当前断点，等待下一个断点 |
| Step Over | `F8` | 执行当前行，但不进入方法内部 |
| Step Into | `F7` | 只在同一条同步调用链中进入方法 |
| Evaluate Expression | `Alt+F8` | 直接计算 `request.getCallId()` 等表达式 |

本阶段以 `F8` 和 `F9` 为主。不要尝试依靠连续 `F7` 从 Client 线程进入 LogAppender 或 StateMachineUpdater，因为异步边界处不会这样跳转。

### 第四步：断点的基本设置

点击代码左侧行号栏创建红点。程序停住后，在 Debug 窗口中记录：

```text
Threads & Variables 左上角：当前线程名
Frames 左侧：当前调用栈
Variables 右侧：当前方法参数和局部变量
```

如果同一个断点命中过多：

1. 右键断点。
2. 暂时取消 `Suspend` 或取消勾选该断点。
3. 也可以设置 `Condition`，但第一次练习不强制使用条件断点。

本实验的断点建议右键设置：

```text
Suspend: Thread
```

不要使用 `Suspend: All` 长时间挂起整个 MiniRaftCluster。选择 `Thread` 后，其他 Raft 心跳和 RPC 线程仍可运行；同时配合上面的 `disabled_on_debug`，避免 JUnit timeout watcher 在你观察变量时中止测试。

`state.appendLog(context)` 位于 `synchronized (this)` 内，即使只挂起当前线程，它仍暂时持有当前 `RaftServerImpl` 的监视器。因此这里适合快速记录并按 `F8/F9` 放行，不适合停住后离开很长时间。

---

## 6.1 第一轮：Leader 检查与本地 append

### 本轮只回答

```text
请求在哪个节点通过 Leader 检查？
它在哪里第一次拥有 term/index？
```

### 设置断点

先删除或禁用其他断点，只保留：

1. `RaftServerImpl#writeAsyncImpl` 中：

   ```java
   final CompletableFuture<RaftClientReply> reply = checkLeaderState(request);
   ```

2. `RaftServerImpl#appendTransaction` 中：

   ```java
   state.appendLog(context);
   ```

3. `RaftLogBase#appendImpl` 中：

   ```java
   final LogEntryProto e = operation.initLogEntry(term, nextIndex);
   ```

### 启动与观察

在右上角选择 `Day5-Write-Path`，点击虫子图标 Debug。

第一次停在 `writeAsyncImpl` 时：

1. 记录 Debug 左上角线程名。
2. 展开 `request`，记录 `clientId`、`callId`、`raftGroupId` 和 `type`。
3. 展开 `this -> role`，或 Evaluate：

   ```java
   getInfo().isLeader()
   getInfo().isLeaderReady()
   getMemberId()
   ```

4. 按一次 `F8` 执行 `checkLeaderState()`。
5. 观察局部变量 `reply`：

   ```text
   reply == null：Leader 检查通过
   reply != null：当前命中的是非 Leader/未 ready 分支
   ```

如果命中非 Leader，按 `F9`。三节点测试会产生多个服务端事件，等待命中真正处理写请求的 Leader。

停在 `state.appendLog(context)` 之前时：

1. 展开 `context`。
2. 此时不要假设已经存在最终日志 `term/index`。
3. 按 `F8` 执行该行。
4. 再观察：

   ```java
   context.getLogEntry()
   context.getLogEntry().getTerm()
   context.getLogEntry().getIndex()
   ```

停在 `RaftLogBase#appendImpl` 时：

1. 在执行 `initLogEntry` 前记录 `term` 和 `nextIndex`。
2. 按 `F8`。
3. 展开 `e`，确认：

   ```text
   e.term  == term
   e.index == nextIndex
   ```

### 本轮成功标准

能写出一条真实记录：

```text
线程：________
memberId：________
clientId/callId：________ / ________
生成的 term/index：________ / ________
结论：checkLeaderState 返回 null 后才继续；term/index 在 initLogEntry 时形成。
```

完成记录后停止 Debug，不要继续单步等待进入第二轮。

---

## 6.2 第二轮：Leader 向 Follower 复制并推进 commit

### 本轮只回答

```text
哪个 LogAppender 面向哪个 Follower？
成功 reply 如何改变 matchIndex，并触发 commit 计算？
```

### 设置断点

第二轮不要使用会挂起线程的普通断点。`ParameterizedBaseTest` 把选举超时设为 300～600ms，而 LogAppender 正是发送 heartbeat 的线程；人工暂停它会让 Follower 发起新选举。

先禁用第一轮断点，然后设置以下 **Tracepoint（不挂起线程的断点）**：

1. `LogAppenderDefault#sendAppendEntriesWithRetries` 中：

   ```java
   final AppendEntriesReplyProto reply = getServerRpc().appendEntries(proto);
   ```

2. `LogAppenderDefault#handleReply`。
3. `LeaderStateImpl#onFollowerSuccessAppendEntries`。
4. `LeaderStateImpl#updateCommit(long majority, long min)`。

如果你希望同时观察 Follower，可额外添加：

5. `RaftServerImpl#appendEntriesAsync` 中调用 `state.getLog().append(entries)` 附近。

不要同时在 `appendEntriesAsync` 的每一层都下断点，否则 heartbeat 会造成大量重复停顿。

### 把普通断点改成 Tracepoint

对每个红点右键打开属性：

```text
取消 Suspend（或选择 Suspend: None）
勾选 Log message to console
按需勾选 Evaluate and log
```

发送位置增加条件，过滤掉 heartbeat：

```java
proto.getEntriesCount() > 0
```

发送位置的 `Evaluate and log` 可以填写：

```java
"SEND thread=" + Thread.currentThread().getName()
    + ", " + getServer().getMemberId() + " -> " + getFollowerId()
    + ", rpcCallId=" + proto.getServerRequest().getCallId()
    + ", previous=" + proto.getPreviousLog().getTerm()
    + "/" + proto.getPreviousLog().getIndex()
    + ", entries=" + proto.getEntriesCount()
    + ", first=" + proto.getEntries(0).getTerm()
    + "/" + proto.getEntries(0).getIndex()
    + ", last=" + proto.getEntries(proto.getEntriesCount() - 1).getTerm()
    + "/" + proto.getEntries(proto.getEntriesCount() - 1).getIndex()
    + ", leaderCommit=" + proto.getLeaderCommit()
```

这里已经用 Condition `proto.getEntriesCount() > 0` 过滤了 heartbeat，所以表达式中的 `getEntries(0)` 是安全的。不要再拼接整个 `proto`；它会把地址和 `commitInfos` 等内容全部展开，输出可能达到数万行，不利于追踪同一条日志。

`handleReply` 位置可以填写：

```java
"REPLY thread=" + Thread.currentThread().getName()
    + ", follower=" + getFollowerId()
    + ", result=" + reply.getResult()
    + ", term=" + reply.getTerm()
    + ", followerCommit=" + reply.getFollowerCommit()
    + ", matchIndex=" + reply.getMatchIndex()
    + ", nextIndex=" + reply.getNextIndex()
```

`updateCommit(majority, min)` 位置可以填写：

```java
"COMMIT thread=" + Thread.currentThread().getName()
    + ", majority=" + majority + ", min=" + min
    + ", flushIndex=" + raftLog.getFlushIndex()
    + ", oldCommitIndex=" + raftLog.getLastCommittedIndex()
    + ", currentTerm=" + currentTerm
```

Tracepoint 会把证据打印到 Debug Console，但不会暂停 LogAppender，所以不会人为切断 heartbeat。第二轮先用这种方式收集稳定证据；只有在把选举超时专门调大后，才适合在 LogAppender 中使用可挂起断点逐项展开变量。

这里要特别区分方法所在的对象：

```text
LogAppenderDefault 本身没有 getMemberId()。
getServer() 返回 RaftServer.Division，Division 才有 getMemberId() 和 getId()。
getServer().getMemberId() -> 完整成员标识，例如 s1@group-XXXX
getServer().getId()       -> 只有节点标识，例如 s1
getFollowerId()           -> LogAppender 接口的默认方法，等价于 getFollower().getId()
```

因此，在 `LogAppenderDefault` 的断点表达式中不要直接填写 `getMemberId()`；那是 `RaftServerImpl` 等服务端上下文中的方法，不是当前 `LogAppenderDefault` 对象的方法。

如果此前已经因普通断点出现反复 PRE_VOTE、term 快速上涨或 `Leader not ready`，停止当前测试并重新 Debug。集群状态已经受到扰动时，不要继续使用这一轮数据填写正常复制链。

### 为什么这里先使用 LogAppenderDefault

`TestArithmetic#data()` 没有限定 RPC 类型，所以参数化测试依次创建：

```text
第 1 轮：MiniRaftClusterWithSimulatedRpc，节点通常为 s0～s2
第 2 轮：MiniRaftClusterWithGrpc，节点通常为 s3～s5
第 3 轮：MiniRaftClusterWithNetty，节点通常为 s6～s8
```

对应的 LogAppender 是：

```text
Simulated/Netty：ServerFactory 默认创建 LogAppenderDefault
gRPC：GrpcFactory 覆盖 newLogAppender()，创建 GrpcLogAppender
```

所以第一轮记录的 `s1` 属于 Simulated 参数轮次，`GrpcLogAppender` 断点不会命中。为了让 6.2 从测试的第一轮就能观察复制，本节先使用 `LogAppenderDefault`。

如果明确要观察第二个 gRPC 参数轮次，可以把上面的第 2、3 个断点替换为：

```text
GrpcLogAppender#sendRequest
GrpcLogAppender.AppendLogResponseHandler#onNextImpl
```

然后按 `F9` 等待第一轮 Simulated 集群结束，直到 memberId 进入 `s3～s5`。不要要求 Default 和 gRPC 两套实现按完全相同的方法名命中。

### 在发送端观察

停在 `LogAppenderDefault` 的 `getServerRpc().appendEntries(proto)` 调用前，记录：

```java
getServer().getMemberId()        // Leader 完整身份：peerId + groupId
getServer().getId()              // 仅 Leader 的 peerId
getFollowerId()                  // 目标 Follower；继承自 LogAppender 的默认方法
getFollower().getId()            // 与 getFollowerId() 等价
proto.getServerRequest().getCallId() // AppendEntries RPC callId
```

展开 `proto`，观察：

```text
previousLog 的 term/index
entries 数量
第一条和最后一条 entry 的 term/index
leaderCommit
```

注意：这里的 AppendEntries `callId` 不是原始 ClientRequest 的 `callId`。跨链寻找同一条日志，应优先使用 entry 的 `term/index`。

如果 `entries.size == 0`，当前命中的是 heartbeat。按 `F9` 等待携带业务日志的请求，或者继续记录 heartbeat 如何传播 commitIndex。

### 在 Follower 端观察

停在 `RaftServerImpl#appendEntriesAsync` 后：

1. 记录当前 `getMemberId()`，确认它与发送端的 `getFollowerId()` 对应。
2. 展开 `entries`，用 `term/index` 与发送端记录匹配。
3. 观察 `proto.getLeaderCommit()`。
4. 不要把“收到 entries”直接写成“已经 apply”。

### 在 Leader reply handler 观察

停在 `LogAppenderDefault#handleReply` 后：

1. 展开 `reply`，先看结果是否为成功。
2. 记录 `reply.matchIndex`、`reply.nextIndex`、`reply.term`。
3. 在更新前后观察：

   ```java
   getFollower().getMatchIndex()
   getFollower().getNextIndex()
   ```

只有成功 reply 才能作为推进复制进度的证据。失败 reply 可能触发 `nextIndex` 回退，不应记录成“Follower 已复制成功”。

停在 `updateCommit(majority, min)` 后，记录：

```java
majority
min
raftLog.getFlushIndex()
raftLog.getLastCommittedIndex()
currentTerm
```

按 `F8` 经过 `updateCommitIndex` 后，再次观察 `raftLog.getLastCommittedIndex()` 是否前进。若没有前进，检查候选位置是否属于 `currentTerm`，不要直接判定代码异常。

### 本轮成功标准

```text
Leader/Follower：________ -> ________
复制日志 term/index：________ / ________
reply 结果及 matchIndex：________ / ________
majority/min：________ / ________
commitIndex 更新前/后：________ -> ________
结论：一个 LogAppender 只维护一个 Follower 的复制进度。
```

---

## 6.3 第三轮：StateMachine apply 与 Client reply

### 本轮只回答

```text
哪一条 committed 日志修改了 variables？
它如何完成对应 PendingRequest 的 Future？
```

### 设置断点

禁用第二轮断点，只保留：

1. `StateMachineUpdater#applyLog` 中：

   ```java
   final long committed = raftLog.getLastCommittedIndex();
   ```

2. `RaftServerImpl#applyLogToStateMachine`。
3. `ArithmeticStateMachine#applyTransaction` 中：

   ```java
   result = assignment.evaluate(variables);
   ```

4. `RaftServerImpl#replyPendingRequest` 的 `stateMachineFuture.whenComplete(...)` 内。
5. `LeaderStateImpl#replyPendingRequest` 中：

   ```java
   final PendingRequest pending = pendingRequests.remove(termIndex);
   ```

### 在 StateMachineUpdater 观察

记录：

```java
raftLog.getLastCommittedIndex()
getLastAppliedIndex()
nextIndex
next.getTerm()
next.getIndex()
```

确认满足：

```text
nextIndex = appliedIndex + 1
nextIndex <= 本轮观察到的 committed
```

### 在 ArithmeticStateMachine 观察

停在 `assignment.evaluate(variables)` 之前：

1. 记录 `entry.term/index`。
2. 展开 `assignment`。
3. 展开 `variables`，记录目标变量执行前是否存在及旧值。
4. 按 `F8` 执行业务语句。
5. 再看 `variables` 和 `result`，确认业务状态在这里发生变化。

### 在 reply 链观察

停在 `RaftServerImpl#replyPendingRequest` 的回调中：

```text
exception == null：构造 success reply，并设置状态机返回 Message
exception != null：包装 StateMachineException
```

记录 `invocationId` 和 `termIndex`。随后停在 `LeaderStateImpl#replyPendingRequest` 时，观察：

```java
termIndex
pending
reply.isSuccess()
reply.getLogIndex()
```

执行 `pending.setReply(reply)` 后，原先返回给 RPC 层的 Future 才会完成。不要把 `commitIndex` 前进当成 Client 已经收到业务结果。

### 本轮成功标准

```text
StateMachineUpdater 线程：________
commitIndex/appliedIndex：________ / ________
apply 的 term/index：________ / ________
variables 变化：________ -> ________
PendingRequest 是否按相同 TermIndex 找到：________
reply success/logIndex：________ / ________
```

---

## 6.4 断点未命中的排查顺序

按下面顺序排查，不要一次修改很多设置：

1. 确认测试确实在 Debug 模式运行，工具窗口标题应为 `Debug`，不是 `Run`。
2. 确认配置模块是 `ratis-examples`，JRE 是 JDK 11。
3. 确认 VM options 包含 `-Djunit.jupiter.execution.timeout.mode=disabled_on_debug`；否则人工观察超过 100 秒会触发 `BaseTest` 的超时。
4. 确认断点使用 `Suspend: Thread`，不要长时间 `Suspend: All`。
5. 确认命令行测试能够 `BUILD SUCCESS`。
6. 确认断点是实心红点；空心或带警告的断点通常表示源码与已加载字节码不匹配。
7. Maven Reload 后执行：

   ```text
   Build -> Rebuild Project
   ```

8. 检查当前打开的类来自本项目源码，而不是 Maven 依赖中的同名 class。
9. `GrpcLogAppender` 未命中时先看 memberId：`s0～s2` 通常是 Simulated 参数轮次，使用 `LogAppenderDefault`；等到 `s3～s5` 的 gRPC 轮次才会使用 `GrpcLogAppender`。
10. `appendEntriesAsync` 命中过多时，先禁用它，只观察 `sendRequest` 和 reply handler。
11. `ArithmeticStateMachine#applyTransaction` 未命中时，确认运行的是 `TestArithmetic`，不是只测试选举的用例。
12. 参数化测试可能多次启动集群；按 `F9` 等待符合记录条件的一次，不要把每次停顿都当成同一个请求。

如果断点仍未命中，在 notes 中写明：

```text
未命中的断点：
测试名称与 BUILD 结果：
断点图标状态：
实际命中的相邻方法：
采用的静态源码证据：
```

## 6.5 三轮调试时如何关联同一事件

不要只记录线程名，也不要混淆两类 callId：

| 标识 | 主要用途 |
| --- | --- |
| `clientId + ClientRequest.callId` | 关联 Client 请求、重试缓存和最终 reply |
| 日志 `term + index` | 关联本地 append、Follower 复制、commit、apply 和 PendingRequest |
| AppendEntries `callId` | 只关联某一次 Leader-to-Follower RPC 请求与 reply |
| `memberId/followerId` | 判断当前断点属于哪台逻辑节点 |
| 线程名 | 证明三段链运行在不同执行环境 |

第一次练习最重要的是记录 `term/index`。同一次测试中找到相同的 `term/index`，才是在跨线程追踪同一条 Raft 日志。

## 6.6 阶段六检查点

| 轮次 | 要回答的问题 | 建议记录 |
| --- | --- | --- |
| 第一轮 | 请求何时通过 Leader 检查并完成本地 append | request、callId、term/index、线程 |
| 第二轮 | 哪个 LogAppender 向哪个 Follower 复制 | leader、follower、previous、entries、matchIndex |
| 第三轮 | commit 后哪条日志被 apply 并完成回复 | commitIndex、appliedIndex、term/index、业务结果 |

完成三轮后，不要求三次记录的业务日志一定是同一个 index；每轮能够用本轮内部一致的标识证明链路即可。熟练以后再尝试用条件断点跟踪同一个 `term/index`。

---

# Day 5 最终作业

在 `notes/day-05.md` 完成：

## 1. 六时刻表

| 时刻 | 代表方法 | 此时日志存在于哪里 | 能否成功回复 Client | 原因 |
| --- | --- | --- | --- | --- |
| 收到请求 |  |  |  |  |
| Leader 校验通过 |  |  |  |  |
| Leader 本地追加 |  |  |  |  |
| 多数派复制 |  |  |  |  |
| commitIndex 推进 |  |  |  |  |
| 状态机 apply |  |  |  |  |

## 2. 方法链

分三条写，不要强行画成一个同步栈：

```text
Client 请求处理链
Leader -> Follower 日志复制链
commit -> StateMachine apply/reply 链
```

## 3. 回答四个问题

1. 三节点为什么允许一台机器故障？
2. Leader 本地 append 成功为什么还不能回复？
3. 日志复制、日志提交、状态机应用为什么不是同一时刻？
4. `RaftLog` 与 `ArithmeticStateMachine.variables` 各保存什么？

## 4. 三个场景题

1. Leader 有 index 18，但 Follower 都只有 17，此时哪些阶段已经发生？
2. Leader 和 n1 都有 index 18、n2 只有 17，此时为什么可能提交？
3. `commitIndex=18`、`appliedIndex=17` 时，Client reply 与业务状态处于什么阶段？

## 完成标准

- 能把 append、replicate、commit、apply 四个词放到正确顺序。
- 每个阶段至少关联一个实际类和方法，但不要求背诵所有内部辅助方法。
- 能解释 PendingRequest 为什么在本地 append 时创建、在 apply/reply 后移除。
- 能解释三节点多数派是 2，不误写成必须三台全部确认。
- 能说明 StateMachineUpdater 只应用 committed 且尚未 applied 的日志。

完成后再进入 Day6，把这些 index、Leader 和多数派概念映射到三台 CentOS 的真实日志。
