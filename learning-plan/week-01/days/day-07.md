# Day 7：第一次安全修改——补一个测试并完成跨平台闭环

## 今天为什么重新设计

第一周不适合在 Raft 核心复制路径中随意加日志或改行为。今天只修改 Arithmetic 已有测试，验证一个当前代码已经承诺的行为：非法表达式会抛出 `IllegalArgumentException`。

这样可以练习完整工程流程，同时把风险限制在测试文件：

```text
理解现有行为
  -> 写失败场景测试
  -> Windows 目标测试
  -> TestArithmetic 回归
  -> diff 自审
  -> commit/push/sync
  -> CentOS 同 commit 再验证
  -> 周总结
```

预计用时：3～4 小时。今天不修改 `RaftServerImpl`、`LeaderStateImpl` 或协议代码。

所有预测、测试结果和 Git 证据填写到 `notes/day-07.md`。今天不是照抄一段 JUnit
代码；必须先解释被测行为，再写测试，再证明测试确实执行。

## 完成后你应当能回答

1. 这个测试锁定的是已有行为，还是实现一个新功能？
2. `assertThrows` 的类型参数、Lambda 和返回值分别是什么？
3. 为什么只验证异常类型仍然可能产生“测错行为却通过”的测试？
4. `-pl`、`-am`、`-Dtest` 与 `failIfNoSpecifiedTests` 分别影响什么？
5. 为什么要按目标测试、模块回归、diff 自审、Linux 同 commit 的顺序验证？
6. 如何证明 Windows 与 Linux 验证的是同一份代码？

---

## 今天的唯一代码任务

目标文件：

```text
ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
```

目标行为来自：

```text
ratis-examples/src/main/java/org/apache/ratis/examples/arithmetic/cli/Assign.java
Assign#createExpression(String)
```

当表达式无法匹配数字、变量、一元表达式或二元表达式时，代码会抛出：

```java
IllegalArgumentException("Invalid expression ...")
```

今天只为这个已有行为增加测试，不先修改生产实现。

## 先把任务性质说清楚

本次属于回归/特征测试：生产代码已经定义非法输入会抛异常，我们增加测试把这个行为
固定下来。测试通过不表示今天新增了表达式解析功能，而表示当前实现满足新增的断言。

回答：

1. 如果先修改 `Assign#createExpression()` 再写测试，你将难以区分什么？
2. 为什么测试应调用真实的 `createExpression("a++b")`，而不是在 Lambda 中直接
   `throw new IllegalArgumentException(...)`？

---

# 阶段零：保护工作区

## 0.1 确认分支和状态

在 Windows 的 Ratis 根目录执行：

```powershell
git branch --show-current
git status --short
```

期望分支：

```text
study/week-01
```

如果还有 Day4～Day6 笔记或手册的未提交修改，先确认它们属于你的学习分支。不要使用 `git reset --hard`，也不要删除已有源码修改。

## 0.2 记录修改前 commit

```powershell
git rev-parse HEAD
```

把结果写进 `notes/day-07.md` 的“修改前 commit”。

## 0.3 只看目标生产方法和现有测试

打开：

```text
Assign#createExpression
TestAssignCli#createExpression
```

先回答：

1. 现有测试覆盖了哪些合法表达式？
2. 是否已有非法表达式测试？
3. `"a++b"` 会走到哪个分支？
4. 你预期异常类型和消息关键词是什么？

继续回答：

5. `createExpression` 为什么可以被同包下的 `TestAssignCli` 调用？它是 `public`、
   `private`、`protected` 还是 package-private？
6. 现有 `createExpression()` 测试为什么包含多个 `assertEquals`，但仍算一个测试方法？
7. 新增一个 `@Test` 方法后，Surefire 的 Tests run 预计增加几个？
8. 输入 `"a++b"` 会依次经过哪些判断，最终为什么落入 `Invalid expression` 分支？

把预测写入笔记后再运行基线测试。

---

# 阶段一：建立修改前基线

在 Ratis 根目录执行：

```powershell
.\mvnw.cmd -pl ratis-examples -am `
  "-DskipTests=false" `
  "-Dtest=TestAssignCli" `
  "-Dsurefire.failIfNoSpecifiedTests=false" `
  test
```

记录：

```text
Tests run
Failures
Errors
BUILD SUCCESS/FAILURE
```

基线失败时先停止修改，确认失败是否与当前工作区已有改动有关。

### 阶段一检查点

为什么先跑基线？因为修改后出现失败时，需要区分“本来就失败”和“本次修改引入失败”。

还要确认：

1. `BUILD SUCCESS` 前是否真的出现了 `TestAssignCli` 的测试摘要？
2. 如果上游模块没有匹配 `TestAssignCli`，为什么需要
   `-Dsurefire.failIfNoSpecifiedTests=false`？
3. 这个参数是否会让 `ratis-examples` 中真正失败的目标测试被忽略？

答案写到笔记，不要把“没有匹配测试”和“测试执行后通过”混为一谈。

---

# 阶段二：增加一个非法表达式测试

## 2.1 新测试应该证明什么

不是只证明“发生异常”，而是至少证明：

```text
异常类型是 IllegalArgumentException
异常消息说明是 Invalid expression
```

## 2.2 先理解 `assertThrows`，再输入代码

把下面结构拆成三部分：

```java
final IllegalArgumentException exception = Assertions.assertThrows(
    IllegalArgumentException.class,
    () -> new Assign().createExpression("a++b"));
```

回答：

1. `IllegalArgumentException.class` 是要执行的代码，还是期望的异常类型？
2. Lambda `() -> ...` 是在构造 Lambda 时立即执行，还是由 `assertThrows` 调用？
3. 如果 Lambda 没有抛异常，测试会怎样？
4. 如果抛出 `NullPointerException`，测试会怎样？
5. `assertThrows` 为什么还返回异常对象？

## 2.3 在 TestAssignCli 中增加独立测试方法

建议方法名：

```java
@Test
public void invalidExpression() {
  // 1. 调用 Assertions.assertThrows
  // 2. 执行 new Assign().createExpression("a++b")
  // 3. 保存返回的 IllegalArgumentException
  // 4. 断言异常消息包含 "Invalid expression"
}
```

你可以参考下面的 JUnit 结构，但必须逐项理解：

```java
final IllegalArgumentException exception = Assertions.assertThrows(
    IllegalArgumentException.class,
    () -> new Assign().createExpression("a++b"));
Assertions.assertTrue(exception.getMessage().contains("Invalid expression"));
```

解释：

- `assertThrows` 的第一个参数是预期异常类型；
- Lambda 中的代码是被测试动作；
- `assertThrows` 返回捕获到的异常对象；
- 第二个断言防止代码抛出同类型但完全无关的异常。

将“异常类型正确”和“异常原因正确”分开记录：

| 断言 | 证明什么 | 不足之处 |
| --- | --- | --- |
| `assertThrows(IllegalArgumentException.class, ...)` |  |  |
| message contains `Invalid expression` |  |  |

本练习使用 `contains`，因为完整消息中还包含具体输入和提示文本；测试重点是异常类别，
不是把整段提示的每个字符都冻结。

## 2.4 不要做的额外修改

本阶段不要：

- 修改 `Assign#createExpression` 的实现；
- 顺手格式化整个文件或整个模块；
- 调整正则表达式；
- 新增第三方依赖；
- 把多个不相关测试重命名。

### 阶段二检查点

在运行测试前预测：新增后总测试数会增加多少？如果测试通过，它证明的是生产代码“新增了功能”，还是“已有行为被测试锁定”？

再做一次反向思考：如果把输入误写成合法表达式 `"a+b"`，这个测试应该通过还是失败？
为什么一个好的负向测试必须确保输入真的会进入预期非法分支？

---

# 阶段三：从最小测试逐步扩大验证

## 3.1 先跑最小目标测试

```powershell
.\mvnw.cmd -pl ratis-examples -am `
  "-DskipTests=false" `
  "-Dtest=TestAssignCli" `
  "-Dsurefire.failIfNoSpecifiedTests=false" `
  test
```

检查新增的测试方法确实执行，不能只看 `BUILD SUCCESS`。

Surefire 报告位置：

```text
ratis-examples/target/surefire-reports/
```

记录并解释：

1. `-pl ratis-examples` 选择了什么？
2. `-am` 为什么会构建依赖模块？
3. `-Dtest=TestAssignCli` 筛选的是 Java 主类、生产类还是测试类？
4. 怎样从 Tests run 数量证明新增的独立 `@Test` 方法被执行？
5. 如果新增方法忘记写 `@Test`，为什么项目仍可能 `BUILD SUCCESS`？

## 3.2 再跑 Arithmetic 集成回归

```powershell
.\mvnw.cmd -pl ratis-examples -am `
  "-DskipTests=false" `
  "-Dtest=TestArithmetic" `
  "-Dsurefire.failIfNoSpecifiedTests=false" `
  test
```

预期仍为 6 个 TestArithmetic 用例通过。

## 3.3 为什么要跑两层

```text
TestAssignCli   快速、精确验证表达式解析行为
TestArithmetic  验证真实 Raft 示例主流程没有回归
```

测试范围不是越大越好；先最小定位，再扩大信心。

## 3.4 故意失败实验（建议完成）

为了证明新测试真的有效，可以临时把消息关键词改成一个肯定不存在的字符串，再运行
`TestAssignCli`，观察该测试失败；随后立即改回 `Invalid expression` 并重新运行通过。

这个临时改动只用于本地验证，不提交。记录：

```text
错误关键词时：哪一个断言失败
恢复正确关键词后：Tests run / Failures / Errors
```

不要通过删除断言让测试重新变绿。

---

# 阶段四：Git 自审，不要马上 commit

## 4.1 只看目标文件差异

```powershell
git diff -- ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
```

逐项回答：

1. 是否只新增一个测试方法？
2. 是否意外修改了换行、缩进或许可证头？
3. 测试名是否表达行为，而不是实现细节？
4. 两个断言失败时是否能帮助定位？
5. diff 中是否出现 `Assign.java`？如果出现，是否超出今天范围？

## 4.2 检查空白与全局状态

```powershell
git diff --check
git status --short
```

`git diff --check` 无输出通常表示没有尾随空格等问题。

不要使用：

```powershell
git add .
```

先明确本次准备提交哪些文件。

区分：

```text
git diff             查看未暂存修改
git diff --cached    查看已暂存、将进入 commit 的修改
git status --short   查看文件处于哪种状态
```

回答：只运行 `git diff` 能否完整看到已经 staged 的内容？为什么 commit 前必须再看
`git diff --cached`？

## 4.3 更新学习记录

在 `notes/day-07.md` 写下：

- 修改前预期；
- 实际新增测试；
- 两条 Windows 测试命令与结果；
- `git diff --check` 结果；
- 自审发现。

学习记录是否与代码放在同一 commit，由你当前学习分支的提交组织决定；但不要混入无关源码修改。

---

# 阶段五：创建一个范围明确的 commit

## 5.1 精确暂存

至少暂存测试文件：

```powershell
git add ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
```

如果决定把当天学习记录放进同一提交，再显式添加：

```powershell
git add learning-plan/week-01/notes/day-07.md
```

检查暂存内容：

```powershell
git diff --cached
git status --short
```

此时做提交前门禁：

| 条件 | 是否满足 |
| --- | --- |
| staged diff 只有目标测试和明确选择的笔记 |  |
| 没有生产代码修改 |  |
| 没有临时错误关键词 |  |
| Windows 目标测试通过 |  |
| Windows Arithmetic 回归通过 |  |
| `git diff --check` 无问题 |  |

## 5.2 提交

建议提交说明：

```powershell
git commit -m "test(examples): cover invalid arithmetic expression"
```

记录新 commit：

```powershell
git rev-parse HEAD
```

若 Git 提示没有可提交内容，不要重复 commit；先用 `git status` 查明文件是否真的保存和暂存。

---

# 阶段六：同步到三台 CentOS

同步脚本要求 Windows 工作树没有未暂存修改。先检查：

```powershell
git status --short
```

如果仍有其他学习笔记修改，合理提交或暂存后再同步，不要为了通过脚本而删除它们。

进入脚本目录：

```powershell
cd learning-plan\week-01\scripts\windows
.\Sync-StudyBranch.ps1
```

脚本将：

```text
Windows study/week-01
  -> push 到 remote study
  -> node1/node2/node3 fetch
  -> fast-forward 到相同 study/week-01 commit
```

同步后在三台分别执行：

```bash
cd /home/ratis/src/ratis
git rev-parse HEAD
git branch
git status --short
```

三个 Linux commit 必须等于 Windows 新 commit。

回答：

1. 分支名相同是否足以证明代码相同？
2. 为什么最终以完整 commit hash 为准？
3. Linux 工作树非空时，即使 HEAD 相同，验证结果是否仍可能受本地修改影响？

---

# 阶段七：Linux 交叉验证

任选一台 CentOS，例如 node1：

```bash
cd /home/ratis/src/ratis
./mvnw -pl ratis-examples -am \
  -DskipTests=false \
  -Dtest=TestAssignCli \
  -Dsurefire.failIfNoSpecifiedTests=false \
  test
```

再检查 Surefire 摘要。记录：

- 节点名；
- commit；
- Java/Maven；
- Tests run/Failures/Errors；
- BUILD SUCCESS/FAILURE。

如果 Windows 通过、Linux 失败，先比较 commit、JDK、文件编码和完整错误，不要直接改测试绕过。

## 7.1 跨平台失败时的排查顺序

```text
1. 比较完整 commit hash
2. 检查 git status --short
3. 比较 ./mvnw -version 中 Java/Maven/encoding
4. 确认执行了同一个模块、同一个 -Dtest
5. 阅读第一个实际测试失败或编译错误
```

不要只比较最后一行 `BUILD FAILURE`；它只是结果，不是原因。

---

# 阶段八：第一周复盘

填写 `notes/week-summary.md`，不要只写“学会了很多”。至少完成：

## 1. 三条已经能用源码解释的主线

建议从下列内容中选三条，用自己的话写：

- Maven Reactor 与 Windows/Linux 同 commit 构建；
- JCommander 如何把子命令参数写入对象；
- `Assign -> RaftClient -> GrpcClientRpc`；
- Client 如何通过 NotLeaderException 更新 Leader；
- `append -> replicate -> commit -> apply`；
- 三节点为什么只能容忍一台故障。

## 2. 三个仍不清楚的问题

问题必须具体到类、方法或现象。例如：

```text
我还不理解 LeaderStateImpl 如何从多个 FollowerInfo 计算 majorityIndex。
```

不要只写“Raft 还不熟”。

## 3. 修订两张图

- 修订 Day3 组件图：补充 Day4 Client 路由知识。
- 修订 Day5 写请求时序：补充 Day6 term/Leader/commit 证据。

## 4. 下周入口

建议下周分三条逐步深入：

```text
Leader 选举：RoleInfo / LeaderElection
复制进度：FollowerInfo / LogAppender
快照恢复：StateMachineUpdater / SnapshotInstallationHandler
```

---

# Day 7 最终作业

在 `notes/day-07.md` 保存：

1. 修改前后 commit。
2. 测试新增内容与为什么这样断言。
3. Windows 两层测试证据。
4. `git diff --check` 和 staged diff 自审结果。
5. 三台 Linux commit 对照。
6. 至少一台 Linux 的目标测试证据。
7. 本周总结文件链接。
8. 用自己的话解释 `assertThrows`、Lambda、异常对象和消息断言各自的作用。

## 完成标准

- 只新增一个可解释的非法表达式测试，没有修改 Raft 核心行为。
- Windows 的 `TestAssignCli` 和 `TestArithmetic` 都通过。
- diff 中没有无关格式化或意外文件。
- 有范围明确的 commit，三台 CentOS 与 Windows commit 一致。
- 至少一台 CentOS 重跑 `TestAssignCli` 通过。
- 周总结的问题具体到实际类/方法，不使用空泛表述。

完成 Day7 后，第一周才算形成完整闭环：不是“看过源码”，而是能够定位、解释、验证、修改、自审并跨平台复现。
