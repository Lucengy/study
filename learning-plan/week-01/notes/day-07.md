# Day 7 记录：第一次安全修改与跨平台闭环

> 填写方式：先回答理解题，再修改代码。所有测试都记录“命令 + Tests run/Failures/Errors + BUILD 结果”。

## 0.1 任务性质

1. 本次是在生产代码中新增功能，还是为已有行为增加回归/特征测试？

   **我的答案：**

2. 为什么测试必须调用真实的 `Assign#createExpression("a++b")`？

   **我的答案：**

3. 如果先改生产代码再写测试，会难以区分什么？

   **我的答案：**

## 0.2 修改前工作区

- 当前分支：
- 修改前完整 commit：
- `git status --short`：
- 已有修改的归属说明：

## 0.3 阅读生产方法与现有测试

1. 现有测试覆盖了哪些合法输入类型？

   **我的答案：**

2. `createExpression()` 是什么访问级别？为什么同包测试能调用？

   **我的答案：**

3. 为什么现有方法中有多个断言，但 Surefire 仍把它算作一个测试？

   **我的答案：**

4. 输入 `"a++b"` 依次经过哪些判断？为什么最终进入非法表达式分支？

   **我的答案：**

5. 我的预期：

- 非法输入：
- 异常类型：
- 消息关键词：
- 新增独立 `@Test` 后 Tests run 增加数量：

## 1.1 修改前基线

- 命令：
- Tests run：
- Failures：
- Errors：
- BUILD 结果：
- Surefire 报告位置/证据：

1. 为什么必须先运行基线？

   **我的答案：**

2. 为什么不能只看到 `BUILD SUCCESS` 就断定 `TestAssignCli` 已执行？

   **我的答案：**

3. `-Dsurefire.failIfNoSpecifiedTests=false` 解决什么问题？它会不会忽略真正执行后的失败？

   **我的答案：**

## 2.1 理解 assertThrows

```java
final IllegalArgumentException exception = Assertions.assertThrows(
    IllegalArgumentException.class,
    () -> new Assign().createExpression("a++b"));
```

1. 第一个参数 `IllegalArgumentException.class` 表示什么？

   **我的答案：**

2. Lambda 由谁、在什么时候执行？

   **我的答案：**

3. Lambda 没有抛异常时会怎样？

   **我的答案：**

4. Lambda 抛出 `NullPointerException` 时会怎样？

   **我的答案：**

5. `assertThrows` 为什么返回异常对象？

   **我的答案：**

6. 填写两个断言的边界：

| 断言 | 它证明什么 | 单独使用的不足 |
| --- | --- | --- |
| `assertThrows(IllegalArgumentException.class, ...)` |  |  |
| message contains `Invalid expression` |  |  |

7. 为什么本练习使用 `contains` 而不是完整消息 `equals`？

   **我的答案：**

## 2.2 新增测试

- 测试方法名：
- 测试输入：
- 测试代码位置：
- 为什么使用独立 `@Test`：
- 为什么没有修改 `Assign.java`：
- 新增后 Tests run 预测：

如果输入误写为合法的 `"a+b"`，测试应通过还是失败？为什么？

**我的答案：**

## 3.1 Maven 参数理解

| 参数 | 我的解释 |
| --- | --- |
| `-pl ratis-examples` |  |
| `-am` |  |
| `-DskipTests=false` |  |
| `-Dtest=TestAssignCli` |  |
| `-Dsurefire.failIfNoSpecifiedTests=false` |  |

如果新增方法忘记 `@Test`，为什么构建仍可能成功？怎样从 Tests run 发现？

**我的答案：**

## 3.2 Windows 最小测试与回归

| 测试 | 完整命令 | Tests run/Failures/Errors | BUILD | 与预期是否一致 |
| --- | --- | --- | --- | --- |
| 修改前 TestAssignCli 基线 |  |  |  |  |
| 修改后 TestAssignCli |  |  |  |  |
| TestArithmetic |  |  |  |  |

为什么先运行 TestAssignCli，再运行 TestArithmetic？

**我的答案：**

## 3.3 故意失败实验（建议）

- 临时错误关键词：
- 失败的测试方法：
- 失败的具体断言：
- 错误关键词时结果：
- 恢复 `Invalid expression` 后结果：
- 是否确认临时修改未保留：

这个实验比只看一次绿色构建多证明了什么？

**我的答案：**

## 4.1 Git 自审

1. 三个命令分别能看到什么？

| 命令 | 我的解释 |
| --- | --- |
| `git diff` |  |
| `git diff --cached` |  |
| `git status --short` |  |

2. 只运行 `git diff` 为什么可能漏掉已经 staged 的内容？

   **我的答案：**

3. 目标文件 diff 自审：

| 检查项 | 结果/证据 |
| --- | --- |
| 是否只新增预期测试 |  |
| 是否意外修改生产代码 |  |
| 是否有无关格式化/换行变化 |  |
| 异常类型断言是否正确 |  |
| 消息断言是否正确 |  |
| `git diff --check` |  |

## 5.1 提交前门禁

| 条件 | 是否满足 | 证据 |
| --- | --- | --- |
| staged diff 只有目标测试和明确选择的笔记 |  |  |
| 没有生产代码修改 |  |  |
| 没有保留临时错误关键词 |  |  |
| Windows TestAssignCli 通过 |  |  |
| Windows TestArithmetic 通过 |  |  |
| `git diff --check` 无问题 |  |  |

- staged files：
- commit message：
- 修改后完整 commit：
- commit 后工作树状态：

## 6.1 Windows 与三台 Linux commit 对照

| 环境 | branch | 完整 commit | `git status --short` |
| --- | --- | --- | --- |
| Windows |  |  |  |
| node1 |  |  |  |
| node2 |  |  |  |
| node3 |  |  |  |

1. 分支名相同为什么不足以证明代码相同？

   **我的答案：**

2. HEAD 相同但 Linux 工作树非空，验证结果为什么仍可能不同？

   **我的答案：**

## 7.1 Linux 交叉验证

- 验证节点：
- 完整 commit：
- Java/Maven/encoding：
- 完整命令：
- Tests run/Failures/Errors：
- BUILD 结果：
- Surefire 证据：

Windows 通过、Linux 失败时，我的排查顺序：

```text
1.
2.
3.
4.
5.
```

为什么不能只分析最后一行 `BUILD FAILURE`？

**我的答案：**

## 最终解释：这段测试怎样工作

请不用照抄手册，用自己的话完整解释：

```text
JUnit 怎样调用测试方法
assertThrows 怎样执行 Lambda
异常类型怎样被验证
异常对象为什么被返回
消息断言补充验证了什么
Maven/Surefire 怎样选择并统计这个测试
```

**我的答案：**

## 第一周总结

- 文件：`notes/week-summary.md`
- 我能用源码解释的三条主线：
  1.
  2.
  3.
- 仍不清楚的三个具体问题：
  1.
  2.
  3.
- 下周准备先解决的问题：
