# Day 6 记录：三台 CentOS 集群实验

> 填写方式：每次操作都按“预测—命令/时间—原始证据—解释”记录。未观察到的数据写明原因，不猜测。

## 0.1 机器映射自测

1. `n0`、`192.168.70.110`、`6000`、storage 分别表示什么？

   n0：Raft peer id，是节点在 Raft Group 内的逻辑身份，不是 Linux 主机名。
   192.168.70.110：n0 所在机器的 IP 地址，是网络定位信息。
   6000：n0 的 Ratis Server RPC 监听端口。
   storage：n0 专属的持久化目录，用来保存 Raft 日志、term/vote 元数据、快照等数据。

2. 为什么三台机器可以使用同一个端口？

   端口的占用范围属于各自机器的网络环境。三台机器具有不同的 IP，
   因此 192.168.70.110:6000、192.168.70.111:6000 和
   192.168.70.112:6000 是三个不同的网络端点，不会发生端口冲突。

3. `PEERS` 是完整 group 配置还是当前存活节点列表？停止节点后是否修改？

   PEERS 描述的是 Raft Group 的成员配置，不是当前在线节点列表。
   节点暂时停止只代表该成员不可达，不代表它被移出 Group。

如果停止 n2 后就从 PEERS 删除 n2，相当于把“节点故障”和“成员变更”
混为一谈。真正的成员变更应通过 Raft 配置变更流程完成，不能靠某台
机器临时修改启动参数完成。

4. 为什么 Raft id 与 storage 不能随意交叉使用？

   Raft id 是节点的逻辑身份，storage 保存的是该身份过去参与 Raft
   协议时产生的持久化状态，例如日志、currentTerm、votedFor、配置和快照。

因此，storage 不是普通的临时目录，而是某个 Raft 节点的历史身份和状态。
如果 n0 使用 n1 的 storage，n0 就可能以 n0 的身份加载 n1 的历史数据，
造成节点身份、日志状态或 Group 信息不匹配，可能启动失败，也可能破坏
实验结果和 Raft 的安全性。

所以每个 Raft id 必须始终使用自己的 storage：
n0 对应 n0 目录，n1 对应 n1 目录，n2 对应 n2 目录。
节点正常重启时也必须继续使用原来的专属目录。

## 0.2 故障预测

| 存活节点数 | 进程能否运行 | 是否有多数派 | 能否选出/保持 Leader | 新写入能否提交 | 我的理由       |
| --- |--------|--------|----------------|---------|------------|
| 3 | 能      | 是      | 是              | 是       | 因为符合多数派提交  |
| 2 | 能      | 是      | 是              | 是       | 因为符合多数派提交  |
| 1 | 能      | 否      | 否              | 否       | 因为不符合多数派提交 |

三节点多数派的计算过程：

floor(3/2)+1=2

我确认本实验不会删除/复制 storage、修改 id 复用目录或随意 kill 未确认进程：

确认，这些操作可能对导致集群元数据混乱，严重可能导致集群不可用

## 1.1 环境核对

| 节点 | Raft id | branch | commit | 工作树 | Java/Maven/编码                                         | 6000 端口 | storage |
| --- | --- | --- | --- |-----|-------------------------------------------------------|--------| --- |
| node1 | n0 | study/week-01 | 23904e618549ebdd18652a2daa45426341981759 | 空   | 3.9.9 /11.0.21/UTF-8| 未监听    | `/home/ratis/data/week-01/arithmetic/n0` |
| node2 | n1 |  study/week-01| 23904e618549ebdd18652a2daa45426341981759 | 空   | 3.9.9 /11.0.21/UTF-8|  未监听   | `/home/ratis/data/week-01/arithmetic/n1` |
| node3 | n2 |study/week-01  |23904e618549ebdd18652a2daa45426341981759  | 空   | 3.9.9 /11.0.21/UTF-8 | 未监听 | `/home/ratis/data/week-01/arithmetic/n2` |

1. 分支相同、commit 不同时是否算环境一致？

   不一致

2. commit 相同、工作树非空时是否算实际源码一致？

   不一致

3. `-pl ratis-examples -am` 的作用是什么？`-DskipTests` 说明了什么、没有证明什么？

   -pl ratis-examples 表示选择 ratis-examples 作为本次 Reactor 构建的目标模块；-am 表示同时构建该模块在当前 Reactor 中依赖的上游模块。它并不是重新构建本地仓库中的所有第三方依赖。
   -DskipTests 表示不执行测试用例，但通常仍会编译测试源码；因此本次 BUILD SUCCESS 能证明相关模块完成了编译和打包，不能证明测试用例全部通过。

4. 构建命令和 jar 检查结果：

```text
./mvnw -pl ratis-examples -am   -DskipTests   -Dcheckstyle.skip   -Drat.skip   package
-rw-r--r--. 1 root root 23M Jul 22 22:15 ratis-examples/target/ratis-examples-3.3.0-SNAPSHOT.jar
-rw-r--r--. 1 root root 60K Jul 22 09:24 ratis-examples/target/ratis-examples-3.3.0-SNAPSHOT-tests.jar
```

### 启动前门禁

| 条件                 | 是否满足 | 证据/问题                                                  |
|--------------------|------|--------------------------------------------------------|
| 三台 commit 一致       | 是    | git rev-parse HEAD显示一致                                 |
| 工作树无未解释修改          | 是    | git status --short显示为空                                 |
| 6000 未被未知进程占用      | 是    | ss -ntlp                                               |grep 6000显示为空              |
| 三台构建成功且 jar 存在     | 是    | ls -lh ratis-examples/target/ratis-examples-*.jar有对应结果 |
| id、IP、storage 映射确认 | 是    |   三个启动命令分别使用 n0/n1/n2 对应的专属 storage。                                                     |

## 2.1 启动与初始选主

| 节点 | 启动时间 | PID | 监听地址 | 当前角色     | term | 日志证据（时间+关键词）                                                                                                                                                      |
| --- | --- | --- |------|----------|------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| n0 | 22:19 |25072  | 6000 | leader   | 1    | Leader n0@group-6F7570313233-LeaderStateImpl is ready since appliedIndex == startIndex == 0                                                                                                                                                                  |
| n1 | 22:19 |5532  | 6000 | follower | 1    | n1@group-6F7570313233: change Leader from null to n0 at term 1 for APPEND_ENTRIES, leader elected after 2186ms                                                    |
| n2 | 22:19 | 18327 | 6000 | follower | 1    | n2@group-6F7570313233: change Leader from null to n0 at term 1 for APPEND_ENTRIES, leader elected after 720ms |

1. 启动顺序为什么不能证明 Leader？

   启动顺序只能说明进程启动的先后，不能决定谁获得多数票。Leader 由选举超时、term、日志新旧程度和投票结果共同决定；后来启动的节点也可能先触发有效选举并获得多数票。

2. 哪些证据支持“一个 Leader、两个 Follower”？

   Leader n0@group-6F7570313233-LeaderStateImpl is ready since appliedIndex == startIndex == 0
   n1@group-6F7570313233: change Leader from null to n0 at term 1 for APPEND_ENTRIES, leader elected after 2186ms
   n2@group-6F7570313233: change Leader from null to n0 at term 1 for APPEND_ENTRIES, leader elected after 720ms

3. 日志里出现 `leader` 单词为什么不一定代表当前节点就是 Leader？

   例如，n2的日志中，搜索leader，出现n2@group-6F7570313233: change Leader from null to n0 at term 1 for APPEND_ENTRIES, leader elected after 720ms，但是leader为n0

4. 三台日志 term 不完全同时出现时，我怎样判断当前 term？

   先在每台日志中寻找最近的角色转换、Leader 更新和 AppendEntries 证据，并结合日志时间判断。当前观察中，n0 在 term 1 转为 Leader；n1、n2 随后在 term 1 通过 AppendEntries 确认 Leader=n0。
   三台证据在相近时间互相吻合，因此当前 term 判断为1。不能机械地只取最后一条包含 term 的日志；如果某台出现更高 term，还要检查该 term 是否完成选举，以及其他节点是否随后接受该 term。

## 3.1 三节点基线写入

| 操作 | 操作前预测                                  | 开始/结束时间            | Client 实际结果 | Server 证据 |
| --- |----------------------------------------|--------------------| --- | --- |
| `a=3` | 三节点存活且有leader，预计成功；产生日志提交，最终a=3        | 22:42:11/22:42:14  |Success: true  | 2026-07-22 22:42:14 INFO  StateMachine:181 - LEADER:n0-1: a = 3 = 3 |
| `b=4` | 三节点存活且有leader，预计成功；产生日志提交，最终b=4        | 22:43:14/22:43:16  |Success: true  | 2026-07-22 22:43:15 INFO  StateMachine:181 - LEADER:n0-3: b = 4 = 4 |
| `c=a+b` | 三节点存活且有leader，预计成功；产生日志提交，最终c=7        | 22:44:02/22:44:03  |Success: true  | 2026-07-22 22:44:03 INFO  StateMachine:181 - LEADER:n0-5: c = (a + b) = 7 |
| `get c` | 三节点存活且有leader，预计成功，不产生leader提交，最终返回c=7 | 22:45:10/22:45:12  |c=7  |没有打印类似上述日志  |

选择其中一次 `assign` 详细记录：

- 当时 Leader/term： n0/term 1
- 相关 term/index： term1 / index 5
- Leader 本地 append 证据：只能从后续"LEADER:n0-5"已经apply推断此前必然完成过append
- Follower 复制证据：也没有打印对应的 matchIndex，因此无法从当前日志直接确认
  是 n1 还是 n2参与了多数派。
- commit/apply 或成功 reply 证据：`2026-07-22 22:44:03 INFO StateMachine:181 -
  LEADER:n0-5: c = (a + b) = 7`，
  Client 返回 `Success: true`。
- 当前日志无法观察到的字段：ClientId、callId、Leader 本地 append 的准确时间、
  AppendEntries 的目标 Follower、Follower matchIndex、
  各节点 commitIndex/appliedIndex，以及该条日志自身直接打印的 term。

1. `assign` 和 `get` 是否走完全相同的请求类型与 Server 分支？
    不是，'assign'会触发日志复制，多数派确认，状态机apply，但是get是leader直接返回响应

2. Client 成功是否要求两个个 Follower 都已经 apply？

   不需要，只要多数派commit即可

3. Client 成功能否单独证明三台 appliedIndex 完全相同？

   Client成功说明该普通写请求已经满足多数派提交条件，并且 Leader已经 apply并产生成功结果；但它不能证明两个 Follower都已经 apply，
4. 也不能证明回复瞬间三台机器的 appliedIndex完全相同。参与多数派复制的 Follower甚至也可能只是持有该日志，但状态机 apply仍稍有滞后。

## 4.1 停止 Leader 前的预测

- 将停止的 Leader：n0
- 剩余两台是否有多数派：是
- 立即写入的预测：不断重试，可能达到重试上限返回写入错误
- 新 term 的预测：term=2
- Client 可能观察到的中间现象：返回NotLeaderException，LeaderNotReadyException

## 4.2 Leader 故障时间线

| 时刻 | 时间       | 节点/term   | 原始证据 | 我的解释              |
| --- |----------|-----------| --- |-------------------|
| T0 旧 Leader 停止 | 23:13:52 | n0/term 1 | 2026-07-22 22:42:14 INFO  StateMachine:181 - LEADER:n0-1: a = 3 = 3 | 停止当前leader        |
| T1 开始新选举/term 增加 | 23:13:53 | n1/term 2 |2026-07-22 23:13:53 INFO  RoleInfo:148 - n1: start n1@group-6F7570313233-LeaderElection8  | n1先触发超时选举         |
| T2 新 Leader 产生 | 23:13:54         | n1/term2  |2026-07-22 23:13:54 INFO  RaftServer$Division:390 - n1@group-6F7570313233: changes role from CANDIDATE to LEADER at term 2 for changeToLeader  | n1成功当选为leader     |
| T3 新写入成功 | 23:18:35         | n1/term2  | 2026-07-22 23:18:35 INFO  StateMachine:181 - LEADER:n1-9: d = 4 = 4 | 新leader接收客户端写请求成功 |

- `T2-T1` 选举观察耗时：1
- `T3-T0` 用户恢复观察耗时：4min43s
- 新写入 `d=4` 结果：成功
- `get d` 结果：d=4
- Client 失败/重试/切换证据：Client首先把请求发送给 n2；n2返回 NotLeaderException 并建议 Leader=n1。随后 Client切换到 n1，n1在 index 9 apply d=4，最终请求成功。Client控制台没有打印中间异常，因为重定向/重试由客户端内部完成，但 n2和 n1的 Server日志保留了完整证据。

1. 为什么两台仍能提交？

   因为两台节点仍满足多数派提交

2. term 为什么增加？term 增加是否单独证明已经选出 Leader？

   PreVote阶段不会增加当前 term。PreVote通过后，Candidate发起正式 Election并进入新的 term。本次 n1在 term 1进行 PreVote，通过后发起 term 2选举。
   term增加只能证明节点进入了新一轮正式选举；如果没有获得多数票，该 term仍可能没有 Leader。

3. 已提交的 `c` 为什么仍应可读？

   c=a+b成功回复说明它已经完成多数派提交并在 Leader状态机 apply。未来 Leader必须从与旧提交多数派相交的新多数派中产生，因此已提交结果不会因单个 Leader故障而丢失。
   原日志条目以后可能被 snapshot压缩，但其已提交的业务状态仍会保留。还需要通过新 Leader上的 get c实际验证本次实验结果。

## 5.1 单节点实验

| 节点 | PID/端口状态 | 是否存活 |
| --- |----------|------|
| n0 | 25072         | 否    |
| n1 | 5532         | 否    |
| n2 | 18327         | 是    |

- 唯一存活节点：n2
- 执行 `e=9` 的开始/结束时间：06:53:09，在07:01:00还没有观察到超时退出，我手动ctrl c了
- `timeout` 退出码：255
- Client 原始错误/重试现象：
- Server 角色/选举现象：2026-07-23 06:55:07 INFO  LeaderElection:142 - n2@group-6F7570313233-LeaderElection623 got exception when requesting votes: java.util.concurrent.ExecutionException: org.apache.ratis.thirdparty.io.grpc.StatusRuntimeException: UNAVAILABLE: io exception
  2026-07-23 06:55:07 INFO  LeaderElection:142 - n2@group-6F7570313233-LeaderElection623 got exception when requesting votes: java.util.concurrent.ExecutionException: org.apache.ratis.thirdparty.io.grpc.StatusRuntimeException: UNAVAILABLE: io exception
  2026-07-23 06:55:07 INFO  LeaderElection:206 - n2@group-6F7570313233-LeaderElection623: PRE_VOTE REJECTED received 0 response(s) and 2 exception(s):
  2026-07-23 06:55:07 INFO  LeaderElection:142 -   Exception 0: java.util.concurrent.ExecutionException: org.apache.ratis.thirdparty.io.grpc.StatusRuntimeException: UNAVAILABLE: io exception
  2026-07-23 06:55:07 INFO  LeaderElection:142 -   Exception 1: java.util.concurrent.ExecutionException: org.apache.ratis.thirdparty.io.grpc.StatusRuntimeException: UNAVAILABLE: io exception
  2026-07-23 06:55:07 INFO  LeaderElection:458 - n2@group-6F7570313233-LeaderElection623 PRE_VOTE round 0: result REJECTED
  2026-07-23 06:55:07 INFO  RaftServer$Division:390 - n2@group-6F7570313233: changes role from CANDIDATE to FOLLOWER at term 23 for REJECTED
  2026-07-23 06:55:07 INFO  RoleInfo:141 - n2: shutdown n2@group-6F7570313233-LeaderElection623
  2026-07-23 06:55:07 INFO  RoleInfo:148 - n2: start n2@group-6F7570313233-FollowerState
- 是否收到成功 reply：否

1. 进程仍运行为什么不等于能够提交？

   因为目前集群只有一个节点进程正常，无法满足多数派提交的要求

2. 超时说明“观察窗口内未完成”还是“进程必然崩溃”？

   观察窗口内未完成

3. 失败的 `e=9` 是否可能短暂出现在未提交日志？为什么不能把它当成 committed 业务状态？

   可能出现，它会出现在leader本地的日志中，committed的状态由Leader的commitIndex决定，并不是写入日志中的数据就一定是committed状态

## 6.1 恢复一个节点

### 操作前预测

- 恢复节点/id/storage：192.168.70.110 n0 /home/ratis/data/week-01/arithmetic/n0
- 是否重新具备多数派：是
- 恢复节点是否会直接成为 Leader：不会，从follower开始 2026-07-23 07:14:30 INFO  RaftServer$Division:403 - n0@group-6F7570313233: start as a follower, conf=conf: {index: 0, cur=peers:[n0|192.168.70.110:6000, n1|192.168.70.111:6000, n2|192.168.70.112:6000]|listeners:[], old=null}
- `d` 是否应可读：是
- `e` 是否应成为成功业务状态：重新执行后成功

### 实际证据

- 恢复时间：07:15:15
- 新/当前 Leader 与 term：n2/term 24
- 恢复前日志位置：2026-07-23 07:14:30 INFO  LogSegment:210 - Successfully read 7 entries from segment file /home/ratis/data/week-01/arithmetic/n0/64656d6f-5261-6674-4772-6f7570313233/current/log_inprogress_0
- 恢复后日志位置：2026-07-23 07:15:15 INFO  SegmentedRaftLogWorker:647 - n0@group-6F7570313233-SegmentedRaftLogWorker: created new log segment /home/ratis/data/week-01/arithmetic/n0/64656d6f-5261-6674-4772-6f7570313233/current/log_inprogress_53
- 自动追赶证据：
  2026-07-23 07:15:15 INFO  RaftServer$Division:1748 - n0@group-6F7570313233: Failed appendEntries, previous log entry (t:23, i:52) not found
  2026-07-23 07:15:15 INFO  RaftServer$Division:1667 - n0@group-6F7570313233: appendEntries* reply n2<-n0#0:FAIL-t24,INCONSISTENCY,nextIndex=7,followerCommit=5,matchIndex=-1
  2026-07-23 07:15:15 INFO  RaftServer$Division:1748 - n0@group-6F7570313233: Failed appendEntries, previous log entry (t:23, i:52) not found
  2026-07-23 07:15:15 INFO  RaftServer$Division:1667 - n0@group-6F7570313233: appendEntries* reply n2<-n0#1:FAIL-t24,INCONSISTENCY,nextIndex=7,followerCommit=5,matchIndex=-1
- `get d` 结果：
  2026-07-23 07:18:36 INFO  GrpcConfigKeys:62 - raft.grpc.client.worker-group.size = 0 (default)
  2026-07-23 07:18:36 INFO  RaftClientRequest:315 - Creating RaftClient with clientId client-3538836BC6A3
  2026-07-23 07:18:36 INFO  RaftClientRequest:316 - Creating RaftClient with groupId group-6F7570313233
  2026-07-23 07:18:36 INFO  RaftClientRequest:317 - Creating RaftClient with callId 1
  2026-07-23 07:18:36 INFO  RaftClientRequest:318 - Creating RaftClient with serverId n0
  2026-07-23 07:18:36 INFO  RaftClientRequest:319 - Creating RaftClient with message Message:d
  2026-07-23 07:18:36 INFO  RaftClientRequest:320 - Creating RaftClient with type RO
  2026-07-23 07:18:37 INFO  RaftClientRequest:315 - Creating RaftClient with clientId client-3538836BC6A3
  2026-07-23 07:18:37 INFO  RaftClientRequest:316 - Creating RaftClient with groupId group-6F7570313233
  2026-07-23 07:18:37 INFO  RaftClientRequest:317 - Creating RaftClient with callId 1
  2026-07-23 07:18:37 INFO  RaftClientRequest:318 - Creating RaftClient with serverId n2
  2026-07-23 07:18:37 INFO  RaftClientRequest:319 - Creating RaftClient with message Message:d
  2026-07-23 07:18:37 INFO  RaftClientRequest:320 - Creating RaftClient with type RO
  d=4
  Thu Jul 23 07:18:37 CST 2026
- `get e` 结果及解释：
  Thu Jul 23 07:25:12 CST 2026
  Found /home/ratis/src/ratis/ratis-examples/target/ratis-examples-3.3.0-SNAPSHOT.jar
  2026-07-23 07:25:14 INFO  GrpcConfigKeys:62 - raft.grpc.client.worker-group.size = 0 (default)
  2026-07-23 07:25:14 INFO  RaftClientRequest:315 - Creating RaftClient with clientId client-4143A08E540F
  2026-07-23 07:25:14 INFO  RaftClientRequest:316 - Creating RaftClient with groupId group-6F7570313233
  2026-07-23 07:25:14 INFO  RaftClientRequest:317 - Creating RaftClient with callId 1
  2026-07-23 07:25:14 INFO  RaftClientRequest:318 - Creating RaftClient with serverId n0
  2026-07-23 07:25:14 INFO  RaftClientRequest:319 - Creating RaftClient with message Message:e
  2026-07-23 07:25:14 INFO  RaftClientRequest:320 - Creating RaftClient with type RO
  2026-07-23 07:25:15 INFO  RaftClientRequest:315 - Creating RaftClient with clientId client-4143A08E540F
  2026-07-23 07:25:15 INFO  RaftClientRequest:316 - Creating RaftClient with groupId group-6F7570313233
  2026-07-23 07:25:15 INFO  RaftClientRequest:317 - Creating RaftClient with callId 1
  2026-07-23 07:25:15 INFO  RaftClientRequest:318 - Creating RaftClient with serverId n2
  2026-07-23 07:25:15 INFO  RaftClientRequest:319 - Creating RaftClient with message Message:e
  2026-07-23 07:25:15 INFO  RaftClientRequest:320 - Creating RaftClient with type RO
  e=9
  Thu Jul 23 07:25:15 CST 2026
## 6.2 恢复第三台并最终验证

| 节点 | 恢复时间 | term | commitIndex 证据 | appliedIndex 证据 | 追赶方式/证据 |
| --- | --- | --- | --- | --- | --- |
| n0 |  |  |  |  |  |
| n1 |  |  |  |  |  |
| n2 |  |  |  |  |  |

| 查询 | 结果 |
| --- | --- |
| `get a` |  |
| `get c` |  |
| `get d` |  |

1. 为什么必须使用原 id 和原 storage 恢复？

   为什么使用原id，因为raft ring的配置并没有改变，只有原id才会被认为是同一个raft group成员。
   为什么使用原storage恢复，这是为了防止storage改变后，节点在恢复时读到其他状态，可能对集群照成损坏

2. 为什么不需要复制 Leader 的 storage？

   因为raft本身支持通过appendEntries，将集群恢复为正常状态，无需复制leader 的storage

3. 本次是补日志还是安装 snapshot？证据不足时明确记录。

   补日志，因为leader并没有发生take snapshot，相关的log并没有被purge

4. Client 查询成功为什么不能单独证明三台都追赶完成？

   Client查询成功，只能证明目前leader存活且健康，并不能证明follower的日志追赶情况

## 最终事件时间线

| 时间 | 存活节点 | term | Leader | 操作 | Client 结果 | Server 证据 |
| --- | --- | --- | --- | --- | --- | --- |
|  | 3 |  |  | 基线写入 |  |  |
|  | 2 |  |  | Leader 停止后写入 |  |  |
|  | 1 |  |  | 超时保护写入 |  |  |
|  | 2 |  |  | 恢复一台 |  |  |
|  | 3 |  |  | 全部恢复 |  |  |

## 预测与实际对照

| 场景 | 原预测 | 实际 | 不一致原因/修正理解 |
| --- | --- | --- | --- |
| 三节点 |  |  |  |
| 两节点 |  |  |  |
| 单节点 |  |  |  |
| 节点恢复 |  |  |  |

## 源码映射

| 实际现象 | 对应类/字段 | 我的理解 |
| --- | --- | --- |
| Leader/term 变化 |  |  |
| Follower 日志追赶 |  |  |
| commitIndex 变化 |  |  |
| appliedIndex 变化 |  |  |

## 最终解释题

1. 为什么启动顺序不决定 Leader？

   **我的答案：**

2. 为什么两节点仍可写，而单节点不可写？

   **我的答案：**

3. 为什么失败的 Client 尝试不能当成 committed 数据？

   **我的答案：**

4. 为什么 Client get 成功不能单独证明所有 Follower 已追赶完成？

   **我的答案：**
