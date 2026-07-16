# Day 6：三台 CentOS 集群与故障实验

## 目标

把源码理解映射到真实三机行为，观察选主、写入、故障和恢复。预计 3～4 小时。

## 任务

- [ ] 三台节点拉到相同 commit，并执行 `./mvnw -DskipTests -Dcheckstyle.skip -Drat.skip package`。
- [ ] 在每台节点创建独立存储目录 `/tmp/ratis/n0`、`n1`、`n2`，确认目录可写。
- [ ] 设置 `PEERS=n0:<node1-ip>:6000,n1:<node2-ip>:6000,n2:<node3-ip>:6000`，分别在三台节点运行 Arithmetic server：

  ```bash
  ratis-examples/src/main/bin/server.sh arithmetic server \
    --id n0 --storage /tmp/ratis/n0 --peers "$PEERS"
  ```

  node2/node3 分别替换为 `n1`/`n2` 和对应存储目录。建议用三个 SSH 窗口，第一周先不要后台化，以便直接观察日志。

- [ ] 从任一节点执行 assign/get：

  ```bash
  ratis-examples/src/main/bin/client.sh arithmetic assign --name a --value 3 --peers "$PEERS"
  ratis-examples/src/main/bin/client.sh arithmetic assign --name b --value 4 --peers "$PEERS"
  ratis-examples/src/main/bin/client.sh arithmetic get --name a --peers "$PEERS"
  ```

- [ ] 从日志确认 Leader；停止 Leader 进程，记录重新选主耗时，再次 assign/get。
- [ ] 恢复旧 Leader，观察其追赶日志；随后再停止另一台，验证三台恢复后数据一致。
- [ ] 保存三节点关键日志到本周 `logs/`（目录不提交），在 `notes/day-06.md` 只摘录时间、term、leaderId、commitIndex 等证据。

## 完成标准

- 正常三节点可写；停止 Leader 后剩余两节点仍能恢复写入；只剩一节点时不能形成多数派写入。
- 旧节点恢复后能追赶，不通过手工复制数据“修复”。
- 记录中能把 term/Leader 变化与 Day 5 源码类对应起来。

