# Day 1 记录

- 日期：20260715
- 用时：1.5h
- 当前 commit：
```
    81a3284e
```
- 环境检查输出：
    ```
    Ratis study environment check
    Repository: D:\software\idea_workstation\ratis_20260610\ratis
    [PASS] Git: git version 2.42.0.windows.2
    [PASS] Java 11: java version "11.0.20" 2023-07-18 LTS
    [PASS] Maven: Apache Maven 3.9.5 (57804ffe001d7215b5e7bcb531cf83df38f93546)
    Java version: 11.0.20, vendor: Oracle Corporation, runtime: D:\software\jdk11J
    [PASS] Maven Wrapper: mvnw.cmd
    [PASS] Root POM: pom.xml
    
    Git status (read-only):
    ## study/week-01
    M ratis-client/src/main/java/org/apache/ratis/client/impl/OrderedAsync.java
    M ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/ArithmeticStateMachine.java
    M ratis-grpc/src/main/java/org/apache/ratis/grpc/client/GrpcClientProtocolClient.java
    M ratis-grpc/src/main/java/org/apache/ratis/grpc/server/GrpcLogAppender.java
    M ratis-grpc/src/main/java/org/apache/ratis/grpc/server/GrpcServerProtocolService.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/FollowerState.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/LeaderStateImpl.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/PendingStepDown.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/RaftServerImpl.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/ServerImplUtils.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/ServerState.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/SnapshotInstallationHandler.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/StateMachineUpdater.java
    M ratis-server/src/main/java/org/apache/ratis/server/impl/VoteContext.java
    M ratis-server/src/main/java/org/apache/ratis/server/leader/LogAppenderBase.java
    M ratis-server/src/main/java/org/apache/ratis/server/raftlog/RaftLogBase.java
    M ratis-server/src/main/java/org/apache/ratis/server/raftlog/segmented/LogSegment.java
    M ratis-server/src/main/java/org/apache/ratis/server/raftlog/segmented/SegmentedRaftLog.java
    M ratis-server/src/main/java/org/apache/ratis/server/raftlog/segmented/SegmentedRaftLogCache.java
    M ratis-server/src/main/java/org/apache/ratis/server/raftlog/segmented/SegmentedRaftLogOutputStream.java
    M ratis-server/src/main/java/org/apache/ratis/server/raftlog/segmented/SegmentedRaftLogReader.java
    ?? learning-plan/
    
    Expected baseline: Java 11 on Windows and all three CentOS nodes.
    ```
- 模块分类：
``` 
    API：ratis-client、ratis-server-api
    核心实现：ratis-common、ratis-server
    RPC：ratis-grpc、ratis-netty
    示例：ratis-examples
    测试：ratis-test 及各模块的 src/test
```
- 构建命令与结果：
 命令
```shell
    ./mvnw clean package -DskipTests 
```
 结果
```
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for Apache Ratis 3.3.0-SNAPSHOT:
[INFO] 
[INFO] Apache Ratis ....................................... SUCCESS [  2.178 s]
[INFO] Apache Ratis Documentation ......................... SUCCESS [  1.525 s]
[INFO] Apache Ratis Protocols ............................. SUCCESS [ 13.803 s]
[INFO] Apache Ratis Common ................................ SUCCESS [  7.448 s]
[INFO] Apache Ratis Client ................................ SUCCESS [  2.784 s]
[INFO] Apache Ratis Server API ............................ SUCCESS [  2.891 s]
[INFO] Apache Ratis Metrics API ........................... SUCCESS [  1.344 s]
[INFO] Apache Ratis Metrics Default Implementation ........ SUCCESS [  2.415 s]
[INFO] Apache Ratis Server ................................ SUCCESS [  8.710 s]
[INFO] Apache Ratis - Resource Bundle ..................... SUCCESS [  0.565 s]
[INFO] Apache Ratis gRPC Support .......................... SUCCESS [  3.814 s]
[INFO] Apache Ratis Netty Support ......................... SUCCESS [  3.293 s]
[INFO] Apache Ratis Shell ................................. SUCCESS [  2.870 s]
[INFO] Apache Ratis Test .................................. SUCCESS [  6.286 s]
[INFO] Apache Ratis Tools ................................. SUCCESS [  1.354 s]
[INFO] Apache Ratis Examples .............................. SUCCESS [  6.369 s]
[INFO] Apache Ratis Metrics Dropwizard 3 Implementation ... SUCCESS [  2.275 s]
[INFO] Apache Ratis Project Assembly ...................... SUCCESS [  4.799 s]
[INFO] Apache Ratis BOM ................................... SUCCESS [  0.367 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:18 min
[INFO] Finished at: 2026-07-15T09:59:49+08:00
[INFO] ------------------------------------------------------------------------
[INFO] 283 goals, 281 executed, 2 from cache
```
- 今日疑问：
    1. 有关BUILDING.md中描述的ThirdParty，如何理解，为什么这么安排；什么是skipShade？
- 明日第一步：
  配置三台 CentOS 的固定 IP、SSH 和 JDK 11。

