# Day 1：Windows 开发基线

## 目标

确认源码状态，固定 JDK 11，并得到一次可复现的 Windows 构建结果。预计 2～3 小时。

## 任务

- [ ] 用 `git status --short --branch` 记录当前分支和已有修改。若出现 `dubious ownership`，执行：

  ```powershell
  git config --global --add safe.directory D:/software/idea_workstation/ratis_20260610/ratis
  ```

  这会信任当前仓库；先确认路径确实是你自己的仓库。不要清理或覆盖已有修改。

- [ ] 立即建立学习分支：`git switch -c study/week-01`。若已有同名分支则 `git switch study/week-01`。当前仓库已有的未提交修改会随工作区保留；先确认这些都是你需要的修改。
- [ ] 安装 64 位 JDK 11（若已有则跳过），配置 `JAVA_HOME`，确保新终端中的 `java -version` 与 `mvn -version` 都指向 JDK 11。
- [ ] 运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-StudyEnvironment.ps1`，将输出粘贴到 `notes/day-01.md`。
- [ ] 在 IDE 中把 Project SDK、Maven Runner JRE 都设为同一个 JDK 11；项目编码设为 UTF-8。
- [ ] 阅读根目录 `README.md`、`BUILDING.md` 和根 `pom.xml` 的 `<modules>`，把模块按 API、实现、RPC、示例、测试五类记录下来。
- [ ] 首次构建：`.\mvnw.cmd -DskipTests -Dcheckstyle.skip -Drat.skip clean package`。首次下载依赖较慢，只记录真实结果，不为了“通过”随意改源码。

## 完成标准

- `java -version`、Maven 使用的 Java 都是 11。
- 能说明根项目至少五类模块的职责。
- 构建成功；若失败，`notes/day-01.md` 中有完整首个错误、执行命令和下一步，不只写“构建失败”。

## 可选加餐：Maven 与 ThirdParty

如果对 `BUILDING.md` 中的 ThirdParty、shading、relocation 或 `skipShade` 不熟悉，到与 Ratis 仓库平级的独立工作区 `ratis-labs`，从 `lab-01-hello-maven` 开始按顺序学习。不要直接跳到 shading；完整路径为 `D:\software\idea_workstation\ratis_20260610\ratis-labs`。
