# Day 7记录：第一次安全修改与跨平台测试闭环

> 只填写已经完成的同编号实验。先看代码或运行命令，再记录证据；不要提前猜后续答案。

---

# 阶段 0：保护工作区并建立任务边界

## 0.1 当前状态

```text
当前分支：study/week-01
修改前完整commit：84bb10891ea6a048050e554c606c9d78770de175
git status --short原始输出：
 M learning-plan/week-01/notes/day-06.md
 M learning-plan/week-01/notes/day-07.m
```

已有修改的归属：

```text
文件：learning-plan/week-01/notes/day-06.md day-07.md
为什么存在：因为是我的笔记
是否属于本次Day 7提交：不属于
```

## 0.2 已有行为与测试目标

生产代码已经做了什么：

```text
Assign#createExpression()已经能够解析合法表达式；
当输入不能完整匹配数字、变量、二元表达式或一元表达式时，
会抛出IllegalArgumentException，消息包含Invalid expression。
```

今天准备增加的测试要证明什么：

```text
验证 Assign#createExpression("a++b")会抛出 IllegalArgumentException，并且异常消息包含 "Invalid expression"，从而证明异常确实来自非法表达式分支。
```

今天是否需要修改 `Assign.java`，为什么：

```text
不需要，我们只是测试业务代码，即Assign.java中的逻辑能否处理非法的表达式
```

---

# 阶段 1：手把手阅读现有代码

## 1.1 现有 `TestAssignCli`覆盖了什么

从 `TestAssignCli#createExpression()`逐条抄出输入，并按照实际测试分类：

| 输入字符串  | 数字/二元/一元 | 是否包含变量 | 预期表达式结构   |
|--------|----------|--------|-----------|
| 2.0    | 数字       | 否      | 2.0       |
| 42     | 数字       | 否      | 42.0      |
| 2*a    | 二元       | 是      | 2.0 * a   |
| v1 * 2 | 二元       | 是      | v1 * 2.0  |
| 2 + 1  | 二元       | 否      | 2.0 + 1.0 |
| 1 - 6  | 二元       | 否      | 1.0 - 6.0 |
| a+v2   | 二元       | 是      | a + v2    |
| v1 + b | 二元       | 是      | v1 + b    |

解释下面断言比较的两侧分别是什么：

```java
Assertions.assertEquals(
    SQRT.apply(new Variable("ABC")),
    new Assign().createExpression("√ABC"));
```

我的解释：

```text
左侧：手工创建一个一元表达式，运算符是SQRT，
操作数是Variable("ABC")。
右侧：调用真实的Assign#createExpression("√ABC")，
让解析器把字符串解析为实际表达式对象。
这条断言是否已经给ABC赋值并计算平方根：没有
```

## 1.2 数字和变量快速分支

### 输入 `"42"`

| 检查 | 结果  | 下一步                  |
| --- |-----|----------------------|
| `NUMBER_PATTERN.matches()` | 是   | 构造一个DoubleValue对象并返回 |
| `Variable.PATTERN.matches()` | 未执行 | 上一步已经return          |

最终返回的对象：

```text
new DoubleValue("42.0")
```

### 输入 `"ABC"`

| 检查 | 结果 | 下一步            |
| --- |----|----------------|
| `NUMBER_PATTERN.matches()` | 否  | 进入下一个分支        |
| `Variable.PATTERN.matches()` | 是  | 返回一个Variable对象 |

最终返回的对象：

```text
new Variable("ABC")
```

`Matcher.matches()`要求完整匹配还是部分包含：

```text
正则表达式完整匹配
```

## 1.3 二元和一元表达式

### 输入 `"2*a"`

```text
数字分支：否
变量分支：否
binaryMatcher：是
unaryMatcher：否
firstElement：2
operator：*
secondElement：a
递归解析过程：1. 正则完整匹配。
2. 从Matcher提取操作数和运算符字符串。
3. 找到对应的Op枚举，例如MULT或SQRT。
4. 递归调用createExpression解析子操作数。
5. 子操作数解析完成后，构造最终表达式对象。
最终表达式结构：new BinaryExpression(
    BinaryExpression.Op.MULT,
    new DoubleValue(2.0),
    new Variable("a"));
```

### 输入 `"√ABC"`

```text
数字分支：否
变量分支：否
binaryMatcher：否
unaryMatcher：是
operator：√
element：ABC
递归解析过程：1. 正则完整匹配。
2. 从Matcher提取操作数和运算符字符串。
3. 找到对应的Op枚举，例如MULT或SQRT。
4. 递归调用createExpression解析子操作数。
5. 子操作数解析完成后，构造最终表达式对象。
最终表达式结构：new UnaryExpression(
    UnaryExpression.Op.SQRT,
    new Variable("ABC"));
```

## 1.4 非法输入 `"a++b"`

按源码执行顺序填写，不要只写“匹配失败”：

| 顺序 | 检查 | 是否匹配                                 | 原因                          |
| ---: | --- |--------------------------------------|-----------------------------|
| 1 | 完整数字 | 否                                    | 不满足NUMBER_PATTERN           |
| 2 | 完整变量名 | 否                                    | 不满足Variable.PATTERN         |
| 3 | 合法二元表达式 | 否                                    | 不满足BINARY_OPERATION_PATTERN |
| 4 | 合法一元表达式 | 否                                    | 不满足UNARY_OPERATION_PATTERN                         |
| 5 | 最终分支 | throw new IllegalArgumentException() |                             |

从源码中原样记录：

```text
异常类型：IllegalArgumentException
完整异常message：Invalid expression a++b Try something like: 'a+b' or '2'
准备由message断言检查的稳定关键词：Invalid expression
```

这里的关键词来自：

```text
[x] exception.getMessage()
[ ] Maven BUILD结果
[ ] Surefire Tests run摘要
```

## 1.5 package-private 与 `@VisibleForTesting`

```text
createExpression()有没有显式访问修饰符：没有
实际访问级别：package-private
Assign所在包：package org.apache.ratis.examples.arithmetic.cli;
TestAssignCli所在包：package org.apache.ratis.examples.arithmetic.cli;
同包测试能直接调用的原因：Assign.createExpression()方法的权限是package-private
@VisibleForTesting是否改变Java访问权限：不能
   该注解实际表达的设计意图：
   向开发者说明设计意图；
   方便代码审查发现不恰当的生产调用；
   供某些 IDE或静态分析工具识别；
   避免将这个方法误认为稳定的包内API。
```

---

# 阶段 2：运行修改前基线

## 2.1 基线命令与原始结果

执行命令：

```powershell
.\mvnw.cmd -pl ratis-examples -am `
  "-DskipTests=false" `
  "-Dtest=TestAssignCli" `
  "-Dsurefire.failIfNoSpecifiedTests=false" `
  test
```

控制台中目标测试的原始摘要：

```text
Running：org.apache.ratis.examples.arithmetic.cli.TestAssignCli
Tests run：1
Failures：0
Errors：0
Skipped：0
BUILD结果：SUCCESS
```

为什么现有方法内部有多个 `assertEquals`，但 `Tests run`仍为1：

```text
因为它们在同一个测试方法体内
```

本次是否确认 `TestAssignCli`真正执行，而不只是看到 `BUILD SUCCESS`：

```text
证据：[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.088 s -- in org.apache.ratis.examples.arithmetic.cli.TestAssignCli
```

## 2.2 根据真实输出理解 Maven参数

| 参数 | 我的解释                   | 本次输出中的对应现象 |
| --- |------------------------| --- |
| `-pl ratis-examples` | 编译ratis-examples子模块    | surefire:3.5.5:test (default-test) @ ratis-examples --- |
| `-am` | 编译ratis-examples所依赖的模块 |  Reactor Build Order |
| `-DskipTests=false` | 不忽略测试代码                | [INFO] --- surefire:3.5.5:test (default-test) @ ratis-examples --- |
| `-Dtest=TestAssignCli` | 测试类为TestAssignCli      |[INFO] Running org.apache.ratis.examples.arithmetic.cli.TestAssignCli  |
| `-Dsurefire.failIfNoSpecifiedTests=false` | 若模块中没有对应的测试类，继续执行不报错   |[INFO] BUILD SUCCESS  |

回答：

```text
上游模块为什么可能找不到TestAssignCli：
    因为TestAssignCli只存在于ratis-examples包内
failIfNoSpecifiedTests=false会不会忽略已经执行后的断言失败：
    不会需略
如果把测试名拼错，为什么仍可能BUILD SUCCESS：
    如果测试名拼错，所有的模块中都找不到对应的测试类，因为-Dsurefire.failIfNoSpecifiedTests=false的缘故，实际上就是没有产生测试事件
除了BUILD SUCCESS，还必须看到哪两项证据：
    [INFO] Running org.apache.ratis.examples.arithmetic.cli.TestAssignCli
    [INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
```

## 2.3 Surefire报告

```text
报告完整路径：[INFO] Running org.apache.ratis.examples.arithmetic.cli.TestAssignCli
报告中的Tests run：1
Failures：0
Errors：0
执行时间：Time elapsed: 0.110 s
```

控制台摘要和报告是否一致：

```text
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.110 s -- in org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[INFO]
[INFO] Results:
[INFO]
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO]
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for Apache Ratis 3.3.0-SNAPSHOT:
[INFO]
[INFO] Apache Ratis ....................................... SUCCESS [  1.546 s]
[INFO] Apache Ratis Protocols ............................. SUCCESS [ 10.274 s]
[INFO] Apache Ratis Common ................................ SUCCESS [  0.905 s]
[INFO] Apache Ratis Client ................................ SUCCESS [  0.735 s]
[INFO] Apache Ratis Server API ............................ SUCCESS [  0.697 s]
[INFO] Apache Ratis Metrics API ........................... SUCCESS [  0.569 s]
[INFO] Apache Ratis Metrics Default Implementation ........ SUCCESS [  0.751 s]
[INFO] Apache Ratis Server ................................ SUCCESS [  0.789 s]
[INFO] Apache Ratis gRPC Support .......................... SUCCESS [  0.635 s]
[INFO] Apache Ratis Netty Support ......................... SUCCESS [  0.609 s]
[INFO] Apache Ratis Shell ................................. SUCCESS [  0.658 s]
[INFO] Apache Ratis Test .................................. SUCCESS [  0.848 s]
[INFO] Apache Ratis Tools ................................. SUCCESS [  0.695 s]
[INFO] Apache Ratis Examples .............................. SUCCESS [  2.162 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  24.206 s
[INFO] Finished at: 2026-07-23T22:35:59+08:00
[INFO] ------------------------------------------------------------------------
[INFO] 166 goals, 159 executed, 7 from cach
```

---

# 阶段 3：用最小实验理解 `assertThrows`

## 3.1 三个组成部分

```java
final IllegalArgumentException exception = Assertions.assertThrows(
    IllegalArgumentException.class,
    () -> new Assign().createExpression("a++b"));
```

逐项解释：

```text
IllegalArgumentException.class：assertThrows期望Lambda抛出的异常类型。

Lambda `() -> ...`：实际执行的代码

谁调用Lambda：在Assertions.assertThrows()方法体内的逻辑调用lambda

什么时候调用：在Assertions.assertThrows()方法体中调用

exception变量保存什么：保存的是lambda抛出的IllegalArgumentException对象
```

按实际调用顺序编号：

```text
[4] createExpression抛出异常
[1] JUnit调用测试方法
[5] assertThrows检查异常类型
[2] 测试方法调用assertThrows
[3] assertThrows执行Lambda
[6] assertThrows返回异常对象
```

## 3.2 三个对照场景

| 场景 | Lambda中的行为 | assertThrows结果             | 原因                                                                            |
| --- | --- |----------------------------|-------------------------------------------------------------------------------|
| A | 合法输入 `"a+b"`，不抛异常 | 抛出AssertionFailedError     | 因为asserThrows期望抛出IllegalArgumentException异常，但lambda实际上没有抛出                    |
| B | 抛 `NullPointerException` | 抛出AssertionFailedError     | 因为asserThrows期望抛出IllegalArgumentException异常，但lambda实际上抛出了NullPointerException |
| C | `"a++b"`抛 `IllegalArgumentException` | IllegalArgumentException对象 | 抛出的异常类型为期望值                                                                   |

“发生任意异常”是否足以让 `assertThrows(IllegalArgumentException.class, ...)`通过：

```text
不可以，只有抛出的异常类型为IllegalArgumentException才能通过
```

## 3.3 类型断言与消息断言

| 断言 | 能直接证明什么                                       | 单独使用时不能证明什么                          |
| --- |-----------------------------------------------|--------------------------------------|
| `assertThrows(IllegalArgumentException.class, ...)` | 我们期望lambda表达式抛出的异常类型为IllegalArgumentException | 不能证明是我们想要测试的业务代码抛出的异常                |
| `exception.getMessage().contains("Invalid expression")` | 我们期望抛出的异常信息中包含"Invalid expression" | 不能证明抛出的异常类型为IllegalArgumentException |

为什么检查 `contains("Invalid expression")`：

```text
消息断言进一步提高了证据的精确性，使我们更有把握确认异常来自非法表达式分支；但它本身并不能形成绝对保证。
```

为什么本练习不使用完整消息 `equals(...)`：

```text
因为使用Invalid expression已经足够用了，如果使用equals会比较复杂，在Assign.createExpression()方法中，异常包含的信息和形参是强相关的
```

---

# 阶段 4：分两步增加正式测试

## 4.1 第一步：只有异常类型断言

新增测试方法：

```java
@Test
public void invalidExpression() {
    Assertions.assertThrows(
            IllegalArgumentException.class,
            () -> new Assign().createExpression("a++b"));
}
```

修改后第一次运行结果：

```text
Tests run：2
Failures：0
Errors：0
Skipped：0
BUILD结果：SUCCESS
```

为什么 `Tests run`应当从1变成2：

```text
因为我们额外加了一个使用@Test注解的测试方法
```

如果仍然是1，优先检查什么：

```text
TestAssignCli中有几个使用@Test修饰的方法
```

## 4.2 合法输入故意失败实验

临时输入：

```text
final IllegalArgumentException e = Assertions.assertThrows(IllegalArgumentException.class, () -> {
        new Assign().createExpression("a+b");
    });
    Assertions.assertTrue(e.getMessage().contains("Invalid expression"));
```

运行结果：

```text
失败测试方法：[ERROR]   TestAssignCli.invalidException:90 Expected java.lang.IllegalArgumentException to be thrown, but nothing was thrown.
Tests run：2
Failures：1
Errors：0
关键失败消息：
[ERROR] Tests run: 2, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 0.099 s <<< FAILURE! -- in org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[ERROR] org.apache.ratis.examples.arithmetic.cli.TestAssignCli.invalidException -- Time elapsed: 0.007 s <<< FAILURE!
org.opentest4j.AssertionFailedError: Expected java.lang.IllegalArgumentException to be thrown, but nothing was thrown.
        at org.junit.jupiter.api.AssertionFailureBuilder.build(AssertionFailureBuilder.java:152)
        at org.junit.jupiter.api.AssertThrows.assertThrows(AssertThrows.java:73)
        at org.junit.jupiter.api.AssertThrows.assertThrows(AssertThrows.java:35)
        at org.junit.jupiter.api.Assertions.assertThrows(Assertions.java:3128)
        at org.apache.ratis.examples.arithmetic.cli.TestAssignCli.invalidException(TestAssignCli.java:90)
        at java.base/java.lang.reflect.Method.invoke(Method.java:566)
        at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
        at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)

[INFO]
[INFO] Results:
[INFO]
[ERROR] Failures:
[ERROR]   TestAssignCli.invalidException:90 Expected java.lang.IllegalArgumentException to be thrown, but nothing was thrown.
[INFO]
[ERROR] Tests run: 2, Failures: 1, Errors: 0, Skipped: 0
```

为什么合法输入会让这个负向测试失败：

```text
因为Assertions.assertThrows期待lambda表达式执行时抛出对应的IllegalArgumentException，但是合法的输入在执行后没有抛出任何异常，故该断言会抛出
AssertionFailedError，导致测试失败
```

恢复为 `"a++b"`后的结果：

```text
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.094 s -- in org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[INFO]
[INFO] Results:
[INFO]
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
[INFO]
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for Apache Ratis 3.3.0-SNAPSHOT:
[INFO]
[INFO] Apache Ratis ....................................... SUCCESS [  1.521 s]
[INFO] Apache Ratis Protocols ............................. SUCCESS [ 11.411 s]
[INFO] Apache Ratis Common ................................ SUCCESS [  0.947 s]
[INFO] Apache Ratis Client ................................ SUCCESS [  0.636 s]
[INFO] Apache Ratis Server API ............................ SUCCESS [  0.611 s]
[INFO] Apache Ratis Metrics API ........................... SUCCESS [  0.598 s]
[INFO] Apache Ratis Metrics Default Implementation ........ SUCCESS [  0.664 s]
[INFO] Apache Ratis Server ................................ SUCCESS [  0.781 s]
[INFO] Apache Ratis gRPC Support .......................... SUCCESS [  0.610 s]
[INFO] Apache Ratis Netty Support ......................... SUCCESS [  0.587 s]
[INFO] Apache Ratis Shell ................................. SUCCESS [  0.550 s]
[INFO] Apache Ratis Test .................................. SUCCESS [  0.707 s]
[INFO] Apache Ratis Tools ................................. SUCCESS [  0.627 s]
[INFO] Apache Ratis Examples .............................. SUCCESS [  2.782 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  25.743 s
[INFO] Finished at: 2026-07-23T23:02:52+08:00
```

是否确认临时合法输入没有保留：

```text
  @Test
  public void invalidException(){
    final IllegalArgumentException e = Assertions.assertThrows(IllegalArgumentException.class, () -> {
        new Assign().createExpression("a++b");
    });
    Assertions.assertTrue(e.getMessage().contains("Invalid expression"));
  }
```

## 4.3 第二步：增加消息断言

最终测试代码：

```java
  @Test
  public void invalidException(){
    final IllegalArgumentException e = Assertions.assertThrows(IllegalArgumentException.class, () -> {
        new Assign().createExpression("a++b");
    });
    Assertions.assertTrue(e.getMessage().contains("Invalid expression"));
  }
```

运行结果：

```text
Tests run：2
Failures：0
Errors：0
BUILD结果：SUCCESS
```

## 4.4 错误关键词故意失败实验

临时错误关键词：

```text
  @Test
  public void invalidException(){
    final IllegalArgumentException e = Assertions.assertThrows(IllegalArgumentException.class, () -> {
        new Assign().createExpression("a++b");
    });
    Assertions.assertTrue(e.getMessage().contains("InvalidAAA expression"));
  }
```

失败结果：

```text
失败测试方法：[ERROR] org.apache.ratis.examples.arithmetic.cli.TestAssignCli.invalidException -- Time elapsed: 0.007 s <<< FAILURE!
失败的具体断言：[ERROR]   TestAssignCli.invalidException:93 expected: <true> but was: <false>
Tests run：2
Failures：1
Errors：0
```

恢复 `"Invalid expression"`后的结果：

```text

```

这个实验比只看到一次绿色构建多证明了什么：
这个实验不仅证明当前正确关键词能够通过，还证明消息断言确实被JUnit执行，
并且能够在关键词错误时让测试失败。因此，这条断言不是没有作用的摆设，
它确实约束了异常消息必须包含"Invalid expression"。

```text
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.077 s -- in org.apache.ratis.examples.arithmetic.cli.TestAssignCli
[INFO]
[INFO] Results:
[INFO]
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
[INFO]
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for Apache Ratis 3.3.0-SNAPSHOT:
[INFO]
[INFO] Apache Ratis ....................................... SUCCESS [  1.671 s]
[INFO] Apache Ratis Protocols ............................. SUCCESS [ 10.505 s]
[INFO] Apache Ratis Common ................................ SUCCESS [  0.865 s]
[INFO] Apache Ratis Client ................................ SUCCESS [  0.631 s]
[INFO] Apache Ratis Server API ............................ SUCCESS [  0.639 s]
[INFO] Apache Ratis Metrics API ........................... SUCCESS [  0.603 s]
[INFO] Apache Ratis Metrics Default Implementation ........ SUCCESS [  0.651 s]
[INFO] Apache Ratis Server ................................ SUCCESS [  0.805 s]
[INFO] Apache Ratis gRPC Support .......................... SUCCESS [  0.679 s]
[INFO] Apache Ratis Netty Support ......................... SUCCESS [  0.706 s]
[INFO] Apache Ratis Shell ................................. SUCCESS [  0.593 s]
[INFO] Apache Ratis Test .................................. SUCCESS [  0.733 s]
[INFO] Apache Ratis Tools ................................. SUCCESS [  0.658 s]
[INFO] Apache Ratis Examples .............................. SUCCESS [  2.746 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  25.500 s
[INFO] Finished at: 2026-07-23T23:34:06+08:00
[INFO] ------------------------------------------------------------------------
[INFO] 166 goals, 159 executed, 7 from cache
```

是否确认临时错误关键词没有保留：

```text
  @Test
  public void invalidException(){
    final IllegalArgumentException e = Assertions.assertThrows(IllegalArgumentException.class, () -> {
        new Assign().createExpression("a++b");
    });
    Assertions.assertTrue(e.getMessage().contains("Invalid expression"));
  }
```

---

# 阶段 5：扩大回归范围

## 5.1 两层测试结果

| 测试 | 完整命令 | Tests run/Failures/Errors | BUILD | 证明范围 |
| --- | --- | --- | --- | --- |
| `TestAssignCli` |  |  |  |  |
| `TestArithmetic` |  |  |  |  |

为什么先运行 `TestAssignCli`：

```text
从最小测试逐步扩大验证
```

为什么还要运行 `TestArithmetic`：

```text
确保我们添加的测试代码没有影响到其他的测试内容
```

`TestArithmetic`通过是否能替代 `TestAssignCli`的精确负向测试：

```text
并不能，极有可能出现TestArithmetic测试通过，但是TestAssignCli不能测试通过的情况
```

---

# 阶段 6：Git 自审

## 6.1 目标文件 diff

```text
目标diff中新增了几个测试方法：一个
是否修改已有合法表达式断言：是
是否出现Assign.java生产代码修改：否
是否保留临时"a+b"：否
是否保留临时错误关键词：否
是否有无关格式化：否
```

## 6.2 空白和全局状态

```text
git diff --check结果：
 warning: in the working copy of 'learning-plan/week-01/notes/day-06.md', LF will be replaced by CRLF the next time Git touches it
 warning: in the working copy of 'learning-plan/week-01/notes/day-07.md', LF will be replaced by CRLF the next time Git touches it
git status --short结果：
 M learning-plan/week-01/notes/day-06.md
 M learning-plan/week-01/notes/day-07.md
 M ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
```

| 命令 | 我的解释                 |
| --- |----------------------|
| `git diff` | 比较工作区和暂存区            |
| `git diff --cached` | 比较暂存区和上一次提交          |
| `git status --short` | 以简洁的方式查看当前工作区和暂存区的状态 |

为什么只运行 `git diff`可能漏掉 staged内容：

```text
因为不加参数的git diff只比较工作区和暂存区的区别，不会查看暂存区和上一次提交的区别
```

## 6.3 精确暂存

```text
实际执行的git add命令：git add ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
staged files：
PS D:\software\idea_workstation\ratis_20260610\ratis> git diff --cached --name-only
ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
git diff --cached检查结果：
--- a/ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
+++ b/ratis-examples/src/test/java/org/apache/ratis/examples/arithmetic/cli/TestAssignCli.java
@@ -84,4 +84,12 @@ public class TestAssignCli {
         MINUS.apply(6.0),
         new Assign().createExpression("-6.0"));
   }
+
+  @Test
+  public void invalidException(){
+    final IllegalArgumentException e = Assertions.assertThrows(IllegalArgumentException.class, () -> {
+        new Assign().createExpression("a++b");
+    });
+    Assertions.assertTrue(e.getMessage().contains("Invalid expression"));
+  }
 }
\ No newline at end of fil
```

为什么本次不直接使用 `git add .`：

```text
因为存在无关本次实验内容的修改
```

---

# 阶段 7：提交、同步和 Linux复验

## 7.1 提交前门禁

| 条件 | 是否满足 | 证据 |
| --- |------| --- |
| `TestAssignCli`为2个测试且通过 | 是    |Tests run: 2, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.096 s -- in org.apache.ratis.examples.arithmetic.cli.TestAssignCli  |
| `TestArithmetic`通过 | 是    |  |
| `git diff --check`无输出 |      |  |
| 没有生产代码修改 | 是    |  |
| 没有临时合法输入 |      |  |
| 没有临时错误关键词 |      |  |
| staged diff范围正确 |      |  |

```text
commit message：
修改后完整commit：
commit后git status --short：
```

## 7.2 Windows与三台 Linux提交对照

| 环境 | branch | 完整commit | `git status --short` |
| --- | --- | --- | --- |
| Windows |  |  |  |
| node1 |  |  |  |
| node2 |  |  |  |
| node3 |  |  |  |

分支名相同为什么不足以证明源码相同：

```text
```

HEAD相同但工作树非空，为什么验证结果仍可能不同：

```text
```

## 7.3 Linux复验

```text
验证节点：
是否确认该节点没有运行Arithmetic Server：
完整commit：
Java版本：
Maven版本：
platform encoding：
完整测试命令：
Tests run：
Failures：
Errors：
BUILD结果：
Surefire报告路径：
```

Windows通过、Linux失败时的排查顺序：

```text
1.
2.
3.
4.
5.
```

为什么不能只分析最后一行 `BUILD FAILURE`：

```text
```

---

# 阶段 8：用自己的话闭环

## 8.1 完整解释

不要逐句照抄手册，用自己的话串起整个过程：

```text
JUnit怎样发现并调用invalidExpression()：

assertThrows在什么时候执行Lambda：

Lambda没有抛异常时为什么失败：

Lambda抛错异常类型时为什么失败：

assertThrows为什么返回异常对象：

消息断言补充证明了什么：

Tests run从1变2证明了什么：

为什么Windows和Linux必须比较完整commit：
```

## 8.2 Day 7最终自检

```text
[ ] 我能逐行解释"a++b"进入非法分支的过程
[ ] 我能区分package-private与@VisibleForTesting
[ ] 我保存了修改前基线
[ ] 我看到了合法输入导致assertThrows失败
[ ] 我看到了错误关键词导致消息断言失败
[ ] 我恢复了所有临时错误
[ ] Windows两层测试通过
[ ] diff自审通过
[ ] Windows与Linux使用相同完整commit
[ ] 至少一台Linux复验通过
```
