# Day 5 记录

## 写请求时序

```text
client request
  -> leader append
  -> follower append
  -> majority
  -> commitIndex
  -> applyTransaction
  -> reply
```

## 对应类与方法

| 阶段 | 类#方法 | 观察 |
| --- | --- | --- |
| 接收请求 |  |  |
| 本地追加 |  |  |
| 复制 |  |  |
| 提交 |  |  |
| 状态机应用 |  |  |

