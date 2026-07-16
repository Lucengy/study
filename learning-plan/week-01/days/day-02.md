# Day 2：CentOS 三节点与 Git 同步闭环

## 目标

让三台 CentOS 具备一致的运行环境，并验证“Windows 提交 -> 远端 -> Linux 拉取”。预计 3 小时。

## 任务

- [ ] 为三台虚拟机设置稳定 IP/主机名，填写 `config/nodes.local.json`；从 Windows 分别执行 `ping` 和 `ssh user@ip`。
- [ ] 将 `bootstrap-centos7.sh` 复制到每台机器后执行：`bash bootstrap-centos7.sh`。脚本只安装 Git、JDK 11、curl、unzip 等工具，不改软件源和防火墙。
- [ ] 三台机器分别执行 `bash check-study-environment.sh`，确认 Java 主版本均为 11、时间同步正常、端口 6000 未被占用。
- [ ] 在你有写权限的 Git 服务上创建 Ratis fork/私有仓库，在 Windows 添加：`git remote add study <你的仓库URL>`。不要把学习分支 push 到 Apache `origin`。
- [ ] Windows 提交本周材料（PowerShell 中分两行执行）：

  ```powershell
  git add learning-plan
  git commit -m "docs: add week 1 Ratis study plan"
  git push -u study study/week-01
  ```

  当前仓库若还有你之前的源码修改，应先确认其用途并单独提交或暂存；同步脚本会拒绝遗漏未提交内容，且绝不能用清理命令丢掉它们。
- [ ] 三台 Linux 首次执行 `git clone -b study/week-01 <你的仓库URL> /home/ratis/src/ratis`，进入仓库后执行 `git remote rename origin study`，再运行 `./mvnw -version`。统一远端名后同步脚本才能在 Windows 和 Linux 上都使用 `study`。
- [ ] Windows 做一个仅修改 `notes/day-02.md` 的提交，运行 `Sync-StudyBranch.ps1`，在三台机器用 `git log -1 --oneline` 核对 commit id 一致。

## 完成标准

- 三台节点都能 SSH 登录、都使用 JDK 11。
- Windows 与三台 Linux 的 `git rev-parse HEAD` 完全一致。
- 同步脚本面对未提交修改时会拒绝执行，Linux 使用 `--ff-only`，不会覆盖节点上的意外修改。
