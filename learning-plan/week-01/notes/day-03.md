# Day 3 记录

## 组件图

```text
Assign
  |
  v
RaftClient
  |
  | client RPC
  v
RaftServer（Leader）
  |
  | 日志复制
  +--------------------------+
  v                          v
RaftServer（Follower）   RaftServer（Follower）

RaftServer
  +-- RaftLog
  +-- StateMachineUpdater
  +-- ArithmeticStateMachine

配置：
RaftProperties、RaftGroup、RaftPeer

网络：
RaftClientRpc、RaftServerRpc
本示例具体使用 gRPC

日志持久化：
RaftLog、RaftStorage、Server 的 storageDir

业务状态：
ArithmeticStateMachine 中的 variables

业务状态快照：
ArithmeticStateMachine.takeSnapshot()
```

RaftPeer.newBuilder()：
[SubCommandBase.java (line 51)](D:/software/idea_workstation/ratis_20260610/ratis/ratis-examples/src/main/java/org/apache/ratis/examples/common/SubCommandBase.java:51)

客户端创建 RaftGroup：
[Client.java (line 42)](D:/software/idea_workstation/ratis_20260610/ratis/ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/cli/Client.java:42)

RaftClient.newBuilder()：
[Client.java (line 45)](D:/software/idea_workstation/ratis_20260610/ratis/ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/cli/Client.java:45)

Server 创建 RaftGroup：
[Server.java (line 72)](D:/software/idea_workstation/ratis_20260610/ratis/ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/cli/Server.java:72)

RaftServer.newBuilder()：
[Server.java (line 74)](D:/software/idea_workstation/ratis_20260610/ratis/ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/cli/Server.java:74)

## 三个问题的初始猜测

1. 客户端如何找到 Leader？
```text
在调用时，需要传入--peers参数，在Client.run()方法中，通过反序列化该参数得到RaftGroup，使用该对象构造RaftClient，在调用相关RPC方法时，由RaftClient
负责寻找leader
```
2. 日志何时提交？
```text
当Leader确保对应raftLog已经committed，即majority数量的RaftServer均已接受对应raftLog后，日志可以被提交
```
3. 状态机何时执行？
```text
当Leader确保对应raftLog已经committed，会在本地stateMachine apply，同时将自己的committedIndex通过RPC发送给follower，follower将committed index
之前的log都在本地stateMachine apply
```
## 测试证据

- 命令：
```text
 .\mvnw.cmd -pl ratis-examples -am "-DskipTests=false" "-Dtest=TestArithmetic" "-Dsurefire.failIfNoSpecifiedTests=false" test
```
- 结果：
```text
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.apache.ratis.examples.arithmetic.TestArithmetic
[INFO] Tests run: 6, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 16.50 s -- in org.apache.ratis.examples.arithmetic.TestArithmetic
[INFO] 
[INFO] Results:
[INFO] 
[INFO] Tests run: 6, Failures: 0, Errors: 0, Skipped: 0
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for Apache Ratis 3.3.0-SNAPSHOT:
[INFO] 
[INFO] Apache Ratis ....................................... SUCCESS [ 13.320 s]
[INFO] Apache Ratis Protocols ............................. SUCCESS [ 27.717 s]
[INFO] Apache Ratis Common ................................ SUCCESS [  5.055 s]
[INFO] Apache Ratis Client ................................ SUCCESS [  2.259 s]
[INFO] Apache Ratis Server API ............................ SUCCESS [  1.445 s]
[INFO] Apache Ratis Metrics API ........................... SUCCESS [  0.752 s]
[INFO] Apache Ratis Metrics Default Implementation ........ SUCCESS [  1.578 s]
[INFO] Apache Ratis Server ................................ SUCCESS [  7.332 s]
[INFO] Apache Ratis gRPC Support .......................... SUCCESS [  2.820 s]
[INFO] Apache Ratis Netty Support ......................... SUCCESS [  1.378 s]
[INFO] Apache Ratis Shell ................................. SUCCESS [  1.451 s]
[INFO] Apache Ratis Test .................................. SUCCESS [  5.415 s]
[INFO] Apache Ratis Tools ................................. SUCCESS [  0.701 s]
[INFO] Apache Ratis Examples .............................. SUCCESS [ 20.736 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:35 min
[INFO] Finished at: 2026-07-19T10:13:07+08:00
[INFO] ------------------------------------------------------------------------
[INFO] 166 goals, 164 executed, 2 from cache
```
