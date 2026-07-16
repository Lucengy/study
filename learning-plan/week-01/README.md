# 第 1 周：建立可重复的 Ratis 源码学习闭环

建议每天 2～3 小时。若时间不足，以每一天的“完成标准”为边界顺延，不要跳过环境验收。

## 本周最终成果

1. Windows 能稳定编译并运行目标测试。
2. 三台 CentOS 7.x 使用相同 JDK，均能从学习分支拉取并编译源码。
3. 能讲清 `Client -> RaftServer -> RaftLog -> StateMachine` 的基本调用关系。
4. 三台虚拟机能运行 Arithmetic 三节点集群，并完成 Leader 故障与恢复实验。
5. 完成一个小型源码修改、对应测试和实验记录。

## 固定环境决策

- **JDK 基线：JDK 11**。仓库 `BUILDING.md` 声明最低 Java 8；第一周统一使用 11，避免 Windows 当前 JDK 25 与 CentOS 工具链差异干扰学习。
- **Maven：优先仓库自带 Wrapper**：Windows 用 `mvnw.cmd`，Linux 用 `./mvnw`。首次执行会下载 Maven 3.9.9，需要网络。
- **同步：Git 提交 + 私有/个人远端**。建议新增名为 `study` 的远端，Windows push，三台 Linux fetch/pull；不要依赖复制整个工作目录。
- **源码编辑：只在 Windows**。Linux 上禁止直接改源码；实验配置若需要长期保留，也先回到 Windows 修改后提交。

> CentOS 7 已进入归档阶段。如果 `yum` 仓库不可用，应先让虚拟机使用你所在网络可访问的 CentOS Vault 或内部镜像；本周脚本不会自动改写系统软件源。

## 开始前填写

复制 [nodes.example.json](config/nodes.example.json) 为 `nodes.local.json`（已被本目录 `.gitignore` 忽略），填入三台虚拟机信息。

```powershell
Copy-Item learning-plan/week-01/config/nodes.example.json learning-plan/week-01/config/nodes.local.json
```

推荐端口为 `6000/tcp`，每台节点一个 Ratis 服务。保证三台虚拟机互相能通过 IP 和该端口访问；不要使用 `127.0.0.1` 组成跨主机集群。

## 每日安排总览

| 天 | 主题 | 核心产出 | 详细任务 |
| --- | --- | --- | --- |
| Day 1 | Windows 基线与仓库保护 | 环境报告、基线构建结果 | [day-01.md](days/day-01.md) |
| Day 2 | 三台 CentOS 与 Git 同步 | 三节点环境验收、同步闭环 | [day-02.md](days/day-02.md) |
| Day 3 | 从 Arithmetic 示例理解 Raft | 一张组件图、示例测试结果 | [day-03.md](days/day-03.md) |
| Day 4 | Client 请求链路 | 调用链笔记、断点记录 | [day-04.md](days/day-04.md) |
| Day 5 | Server、日志与状态机 | 写请求时序笔记、目标测试 | [day-05.md](days/day-05.md) |
| Day 6 | 三机集群与故障实验 | 集群日志、Leader 故障结论 | [day-06.md](days/day-06.md) |
| Day 7 | 小改动、验证与复盘 | patch、测试证据、周总结 | [day-07.md](days/day-07.md) |

## 常用命令

Windows 环境检查：

```powershell
powershell -ExecutionPolicy Bypass -File learning-plan/week-01/scripts/windows/Test-StudyEnvironment.ps1
```

Windows 快速构建：

```powershell
.\mvnw.cmd -DskipTests -Dcheckstyle.skip -Drat.skip clean package
```

只跑示例模块测试（`-am` 同时构建依赖模块）：

```powershell
.\mvnw.cmd -pl ratis-examples -am -DskipTests=false -Dtest=TestArithmetic -Dsurefire.failIfNoSpecifiedTests=false test
```

同步已提交的当前学习分支：

```powershell
powershell -ExecutionPolicy Bypass -File learning-plan/week-01/scripts/windows/Sync-StudyBranch.ps1
```

## 本周目录说明

- `days/`：每天任务与完成标准。
- `notes/`：每天的记录模板，直接在其中填写。
- `config/`：三台虚拟机配置模板。
- `scripts/windows/`：Windows 环境检查与 Git 同步。
- `scripts/linux/`：CentOS 初始化与环境检查。
- Maven 等通用实验统一放在与本仓库平级的 `ratis-labs` 独立工作区，不放入 Ratis 源码树。
