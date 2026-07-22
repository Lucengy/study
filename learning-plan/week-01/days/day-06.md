# Day 6：三台 CentOS 上观察选主、多数派与日志追赶

## 今天为什么重新设计

今天不是“照着三条命令把服务跑起来”，而是用真实现象验证 Day5 的五个概念：

```text
term
Leader
多数派
commitIndex
落后节点追赶
```

实验严格分为准备、正常写入、Leader 故障、失去多数派、节点恢复五个阶段。每个阶段先预测，再执行，再记录证据。

预计用时：4～5 小时。请准备四个终端：三个 Server SSH 窗口和一个 Client/检查窗口。

所有预测、命令结果和解释填写到 `notes/day-06.md`。每个阶段必须按照：

```text
先预测 -> 再操作 -> 保存原始证据 -> 最后解释
```

不要先看结果再补写预测，也不要只写“成功/失败”而不记录 term、Leader、时间和日志。

## 完成后你应当能回答

1. Raft id、主机、监听端口、storage 之间是什么关系？
2. 启动顺序是否决定 Leader？怎样用日志证明实际 Leader？
3. 三节点、两节点、单节点分别能否形成多数派并提交新写入？
4. Leader 故障后为什么会出现短暂不可用，term 为什么增加？
5. 节点恢复后为什么应使用原 storage 自动追赶，而不是复制其他节点目录？
6. Client 查询成功与“三台节点都追赶完成”为什么不是同一个证据？

---

## 本实验机器映射

| Raft id | 主机 | IP | Server 端口 | 存储目录 |
| --- | --- | --- | --- | --- |
| `n0` | node1 / ozone-1 | `192.168.70.110` | `6000` | `/home/ratis/data/week-01/arithmetic/n0` |
| `n1` | node2 / ozone-2 | `192.168.70.111` | `6000` | `/home/ratis/data/week-01/arithmetic/n1` |
| `n2` | node3 / ozone-3 | `192.168.70.112` | `6000` | `/home/ratis/data/week-01/arithmetic/n2` |

三台机器可以使用相同端口，因为 IP 不同。

统一 peer 字符串：

```bash
export PEERS='n0:192.168.70.110:6000,n1:192.168.70.111:6000,n2:192.168.70.112:6000'
```

注意：三个终端中的 `PEERS` 必须逐字一致；Raft id 与当前机器必须对应。

## 机器映射自测

在执行命令前回答：

1. `n0` 是主机名、IP、Raft peer id，还是三者之一？
2. 为什么三台可以都监听 `6000`？
3. 为什么 `n0` 不能使用 `n1` 的 storage 目录？
4. `PEERS` 描述的是“目前存活节点”，还是完整 Raft group 配置？停止节点后是否应删掉它？

---

# 阶段零：写下故障预测

运行任何服务前，先把下表复制到 `notes/day-06.md` 并填写“预测”：

| 存活节点数 | 是否有多数派 | 能否选出/保持 Leader | 新写入能否提交 |
| --- | --- | --- | --- |
| 3 |  |  |  |
| 2 |  |  |  |
| 1 |  |  |  |

三节点多数派为：

```text
floor(3 / 2) + 1 = 2
```

不要把“进程仍在运行”误认为“可以提交写入”。只剩一个节点时进程可以活着，但不能形成多数派。

## 0.1 把“可运行、可选主、可提交”分开

回答：

1. 单个 Server 进程能否保持运行？
2. 单个节点是否可能不断发起选举？
3. 上面两件事是否说明它能提交新写入？
4. 三节点多数派为什么是 2，而不是“超过一半的 Follower”？计算时是否包含 Leader 自己？

## 0.2 写下操作边界

本实验只允许停止和重新启动 Ratis 示例进程。不要执行：

```text
删除 storage
复制另一节点的 storage
更换 Raft id 后复用旧目录
为了让实验通过而修改 PEERS 移除故障节点
杀死无法确认身份的 Java 进程
```

在笔记中确认你理解：`Ctrl+C` 停止的是当前前台 Server；如果进程身份不明确，先用
`ps` 和端口检查，不执行批量 kill。

---

# 阶段一：三台机器只做环境与版本核对

## 1.1 确认 Git commit 一致

在三台机器分别执行：

```bash
cd /home/ratis/src/ratis
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git status --short
```

期望：

- 分支都是 `study/week-01`；
- commit id 完全相同；
- 工作树为空。

如果 commit 不一致，先回到 Windows 完成 commit/push/sync，不要带着三份不同源码做集群实验。

回答：

1. 分支相同但 commit 不同，能否认为源码环境一致？
2. commit 相同但 `git status --short` 非空，能否认为实际运行源码一定一致？
3. 为什么三台都要记录，而不是只检查 node1？

## 1.2 确认 Java/Maven

```bash
./mvnw -version
```

确认使用 Java 11 和 Maven Wrapper 3.9.9。

记录完整的 Java version、Maven version 和 platform encoding，不只写“正常”。

## 1.3 确认 6000 端口未被占用

```bash
ss -lntp | grep ':6000'
```

没有输出表示当前没有进程监听。若有输出，先确认是不是上次遗留的 Ratis Server，不要直接杀死不认识的进程。

## 1.4 构建示例产物

CentOS 7 首次构建如果出现 `GLIBCXX_3.4.21 not found` 或 `CXXABI_1.3.9 not found`，
先停止构建并按照 [CentOS 7 安装 GCC 14.3.0 指导手册](../guides/install-gcc-14.3.0-centos7.md)
安装隔离工具链。不要覆盖 `/lib64/libstdc++.so.6`。

三台分别执行：

```bash
./mvnw -pl ratis-examples -am \
  -DskipTests \
  -Dcheckstyle.skip \
  -Drat.skip \
  package
```

检查：

```bash
ls -lh ratis-examples/target/ratis-examples-*.jar
```

`server.sh`/`client.sh` 会通过 `common.sh` 从 `ratis-examples/target` 找到构建产物。

回答：

1. 为什么这里使用 `-pl ratis-examples -am`？
2. 为什么集群实验前允许 `-DskipTests`，但不能把这次 package 当成测试已通过的证据？
3. jar 存在是否必然说明它由当前 commit 刚刚构建？怎样结合命令结果判断？

## 1.5 创建存储与日志目录

只创建目录，不要在实验中途删除：

node1：

```bash
mkdir -p /home/ratis/data/week-01/arithmetic/n0
mkdir -p /home/ratis/data/week-01/arithmetic-logs/n0
```

node2：

```bash
mkdir -p /home/ratis/data/week-01/arithmetic/n1
mkdir -p /home/ratis/data/week-01/arithmetic-logs/n1
```

node3：

```bash
mkdir -p /home/ratis/data/week-01/arithmetic/n2
mkdir -p /home/ratis/data/week-01/arithmetic-logs/n2
```

本实验使用持久目录而不是 `/tmp`，这样重启进程后仍能观察日志恢复。不要手工复制三个节点的存储目录。

### 阶段一检查点

在笔记中记录三台：commit、Java 版本、Maven 版本、6000 端口检查结果。

以下任一情况存在时不要启动集群：

- 三台 commit 不一致；
- 任一工作树存在未解释修改；
- 6000 被未知进程占用；
- 构建失败或找不到示例 jar；
- Raft id 与 storage 映射没有确认。

---

# 阶段二：启动三台 Server

## 2.1 node1 启动 n0

```bash
cd /home/ratis/src/ratis
export BIN=$PWD/ratis-examples/src/main/bin
export PEERS='n0:192.168.70.110:6000,n1:192.168.70.111:6000,n2:192.168.70.112:6000'

$BIN/server.sh arithmetic server \
  --id n0 \
  --storage /home/ratis/data/week-01/arithmetic/n0 \
  --peers "$PEERS" \
  2>&1 | tee -a /home/ratis/data/week-01/arithmetic-logs/n0/server.log
```

## 2.2 node2 启动 n1

```bash
cd /home/ratis/src/ratis
export BIN=$PWD/ratis-examples/src/main/bin
export PEERS='n0:192.168.70.110:6000,n1:192.168.70.111:6000,n2:192.168.70.112:6000'

$BIN/server.sh arithmetic server \
  --id n1 \
  --storage /home/ratis/data/week-01/arithmetic/n1 \
  --peers "$PEERS" \
  2>&1 | tee -a /home/ratis/data/week-01/arithmetic-logs/n1/server.log
```

## 2.3 node3 启动 n2

```bash
cd /home/ratis/src/ratis
export BIN=$PWD/ratis-examples/src/main/bin
export PEERS='n0:192.168.70.110:6000,n1:192.168.70.111:6000,n2:192.168.70.112:6000'

$BIN/server.sh arithmetic server \
  --id n2 \
  --storage /home/ratis/data/week-01/arithmetic/n2 \
  --peers "$PEERS" \
  2>&1 | tee -a /home/ratis/data/week-01/arithmetic-logs/n2/server.log
```

启动顺序不决定最终 Leader。等待约 10 秒，不要马上执行 Client。

## 2.4 确认监听与进程

在另一个窗口分别检查：

```bash
ss -lntp | grep ':6000'
ps -ef | grep '[r]atis-examples'
```

如果某台没有监听，先看它前台输出，不要继续故障实验。

分别记录：启动命令所在终端、Java PID、监听地址、启动时间。PID 只是进程证据，不能
证明该节点已经加入同一个 Raft group。

## 2.5 从日志找 Leader

分别搜索最近日志：

```bash
grep -Ei 'leader|term' /home/ratis/data/week-01/arithmetic-logs/n0/server.log | tail -n 30
```

node2/node3 替换目录。记录：

| 节点 | 当前角色 | term | 证据原文中的关键词 |
| --- | --- | --- | --- |
| n0 |  |  |  |
| n1 |  |  |  |
| n2 |  |  |  |

不要仅以“最先启动”判断 Leader。

回答：

1. 为什么启动顺序不能作为 Leader 证据？
2. 三台日志中的 term 应怎样比较？如果观察时间点不同，能否机械要求每一行都相同？
3. 什么日志信息能够支持“一个 Leader、两个 Follower”的结论？
4. 只看到某节点打印 `leader` 单词是否足够？要结合上下文判断它是在描述自己、对端，
   还是历史事件。

### 阶段二检查点

必须确认：一个 Leader、两个 Follower、三台均监听，才能进入写入实验。

把“观察结论”和“原始证据”分开填写：结论写角色，证据保留日志时间、term、节点 id
与关键原文；不要只粘贴没有解释的几十行日志。

---

# 阶段三：正常写入，建立基线数据

在任意一台的第四个 SSH 窗口执行：

```bash
cd /home/ratis/src/ratis
export BIN=$PWD/ratis-examples/src/main/bin
export PEERS='n0:192.168.70.110:6000,n1:192.168.70.111:6000,n2:192.168.70.112:6000'
```

依次写入：

```bash
$BIN/client.sh arithmetic assign --name a --value 3 --peers "$PEERS"
$BIN/client.sh arithmetic assign --name b --value 4 --peers "$PEERS"
$BIN/client.sh arithmetic assign --name c --value 'a+b' --peers "$PEERS"
$BIN/client.sh arithmetic get --name c --peers "$PEERS"
```

预期 `c` 的值对应 7。

## 3.1 每条命令执行前先预测

| 操作 | 我的预测 | 实际结果 |
| --- | --- | --- |
| `a=3` |  |  |
| `b=4` |  |  |
| `c=a+b` |  |  |
| `get c` |  |  |

回答：`assign` 是写请求，`get` 是否也一定经过相同的状态机写入链？先根据 Day4/Day5
的请求类型分派回答，不要因为它们使用同一个 CLI 就认为路径完全相同。

记录一次 assign 的：

- Client 是否第一次就命中 Leader；
- 三个 Server 日志中出现的 term/index；
- Leader 日志复制到两个 Follower 的证据；
- Client 得到成功 reply 的时间。

此阶段不要停止任何节点。

## 3.2 建立可比较的基线

至少为一次 `assign` 记录：

```text
Client 命令开始/结束时间
当时 Leader 与 term
请求相关 term/index
Leader 本地 append 证据
至少一个 Follower 复制证据
commit/apply 或成功 reply 证据
```

如果日志级别不足以显示某个字段，明确写“未从当前日志观察到”，再用能够观察到的
Server/Client 结果补充；不要编造 index。

### 阶段三检查点

回答：Client 收到成功时，是否要求三个 Follower 全都已经应用？还是只要求满足当前请求的 Raft 提交/应用条件？结合 Day5 回答。

再回答：Client 的成功输出能证明集群当时可服务，但能否单独证明 n0、n1、n2 的
`appliedIndex` 已经完全相同？

---

# 阶段四：停止当前 Leader，观察重新选主

## 4.1 先写预测

记录：

- 你认为剩余两台能否形成多数派？
- 停止后立即发送请求会成功、失败还是暂时重试？
- 新 Leader 的 term 应保持还是增加？
- 旧 Client 若先联系已停止节点，可能经历什么错误或延迟？

## 4.2 只停止 Leader 进程

回到当前 Leader 的前台窗口，按：

```text
Ctrl+C
```

记录停止时间。不要删除它的存储目录。

停止后在另外两台确认：旧 Leader 的端口确实不再监听或进程确实退出；不要仅凭前台
窗口看起来安静就判断它已经停止。

## 4.3 观察剩余两台

等待并观察日志，记录：

- 选举开始时间；
- 新 term；
- 新 Leader id；
- 从停止到新 Leader 可服务的大致耗时。

把时间线至少拆为：

```text
T0：旧 Leader 停止
T1：某节点开始新选举/term 增加
T2：新 Leader 产生
T3：新写入成功
```

`T3-T0` 是用户观察到的恢复时间，它不一定等于纯选举耗时 `T2-T1`。

## 4.4 再次写入

在 Client 窗口执行：

```bash
$BIN/client.sh arithmetic assign --name d --value 'c+1' --peers "$PEERS"
$BIN/client.sh arithmetic get --name d --peers "$PEERS"
```

如果第一次命中已停止的旧 Leader，观察 Client 的连接失败/重试以及目标切换。

### 阶段四检查点

1. 为什么两台存活节点仍能提交？
2. 为什么 term 会变化？
3. 旧 Leader 停止前已经提交的 `c` 为什么仍应可读？
4. 为什么 term 增加是新一轮领导权的证据之一，但 term 增加本身不一定证明已选出 Leader？
5. 如果写入在切换期间经过重试最终成功，为什么还应保存中间失败/重试证据？

---

# 阶段五：再停止一台，证明单节点不能提交新写入

## 5.1 只保留一台进程

在剩余两台中，再选择一个 Follower 按 `Ctrl+C`，确保只剩一个 Server 进程。

用 PID 和端口分别确认三台状态，并在笔记中写出“哪台存活”，不要只写“剩一台”。

## 5.2 使用超时保护执行写入

```bash
timeout 20s $BIN/client.sh arithmetic assign --name e --value 9 --peers "$PEERS"
echo $?
```

预期：不能成功形成一个新的已提交写入。命令可能重试、超时或返回失败；保存实际错误，不要因为进程仍运行就判定集群可写。

记录：

- 唯一存活节点的角色变化；
- 是否反复发起选举；
- Client 最终结果；
- 为什么这不是数据损坏，而是多数派安全限制。

区分三种结果：

| 现象 | 可以得出的结论 |
| --- | --- |
| Client 很快返回明确失败 | 请求没有成功提交，保存异常 |
| Client 持续重试后被 `timeout` 终止 | 在观察窗口内无法完成，不等于 Server 进程崩溃 |
| Client 返回成功 | 与预期冲突，必须停止并核对是否仍有第二节点/另一集群 |

### 阶段五检查点

如果单节点还能成功提交新的普通写请求，应停止实验并重新确认是否真的只剩一个进程、是否连接了另一套集群、PEERS 是否一致。

不要把失败的 `e=9` 立即当成“日志中绝对不存在”。它可能曾进入某节点的未提交日志；
本阶段要证明的是它没有形成可对外成功确认的新 committed 业务状态。

---

# 阶段六：恢复节点，观察追赶而不是复制目录

## 6.1 先恢复一个节点

使用它原来的 id、原来的存储目录、相同 PEERS，重新执行阶段二对应启动命令。

此时恢复到两个节点，重新具备多数派。观察：

- 是否产生/确认 Leader；
- 落后节点从哪个 index 开始追赶；
- `d` 是否可读；
- 失败的 `e=9` 是否出现。它不应因为 Client 曾尝试过就自动成为已提交状态。

在启动前预测：恢复节点可能带着旧 term、旧日志和原 storage。它加入后是直接成为
Leader，还是先通过 Raft 协议比较 term/log 并恢复正确角色？实际结果用日志回答。

## 6.2 恢复旧 Leader/第三台

再使用原存储目录启动最后一个节点，观察它追赶新的 term 和日志。

禁止：

```text
手工复制其他节点的 storage
删除落后节点数据后伪装成恢复成功
修改 Raft id 复用其他节点目录
```

## 6.3 最终验证

三台都运行后执行：

```bash
$BIN/client.sh arithmetic get --name a --peers "$PEERS"
$BIN/client.sh arithmetic get --name c --peers "$PEERS"
$BIN/client.sh arithmetic get --name d --peers "$PEERS"
```

再从三台日志记录相近的 commit/applied 位置证据。Client 查询成功只能证明集群可服务；节点追赶证据应来自 Server 日志/index，而不能仅靠一次 Client get 推断每台都同步。

回答：

1. 为什么必须使用原 id、原 storage 恢复？
2. 为什么不需要手工复制 Leader 的目录？
3. 落后节点可能通过补日志或安装 snapshot 追赶；本次实际观察到哪一种？如果日志不足，
   写“无法从现有证据区分”，不要猜测。
4. 三台最终都能响应网络，是否足以证明日志位置相同？还需要什么证据？

---

# Day 6 最终作业

在 `notes/day-06.md` 完成四部分。

## 1. 环境表

记录三台 commit、Java、Maven、端口、存储目录。

## 2. 事件时间线

| 时间 | 存活节点 | term | Leader | 操作 | Client 结果 | Server 证据 |
| --- | --- | --- | --- | --- | --- | --- |
|  | 3 |  |  | 基线写入 |  |  |
|  | 2 |  |  | Leader 停止后写入 |  |  |
|  | 1 |  |  | 超时保护写入 |  |  |
|  | 2 |  |  | 恢复一台 |  |  |
|  | 3 |  |  | 全部恢复 |  |  |

## 3. 预测与实际对照

解释存活 3/2/1 台时能否写入，若实际和预测不同，说明原因。

## 4. 源码映射

至少把实际日志中的现象映射到：

```text
LeaderStateImpl
LogAppender
RaftLog commitIndex
StateMachineUpdater appliedIndex
```

## 5. 四个解释题

1. 为什么启动顺序不决定 Leader？
2. 为什么旧 Leader 停止后两节点仍可写，而单节点不可写？
3. 为什么失败的 Client 尝试不能当成 committed 数据？
4. 为什么 Client get 成功不能单独证明所有 Follower 已追赶完成？

## 完成标准

- 三节点正常可写，记录了一个基线变量。
- 停止 Leader 后，两节点重新选主并恢复写入。
- 只剩一节点时，新写入无法提交。
- 恢复节点使用原存储自动追赶，没有手工复制数据。
- 能用“多数派”解释行为，而不是只写“服务好了/坏了”。
- 能区分 Client 查询结果与每台 Server 已追赶完成的证据。

完成后再进入 Day7，做一个只修改测试代码的低风险练习，并走完 Windows -> Git -> Linux 验证闭环。
