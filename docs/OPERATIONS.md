# 运维与恢复

## 检查

`docker compose ps` 查看健康状态；`docker compose logs --tail=100 app` 看服务错误；`docker compose exec app python3 deploy/healthcheck.py` 核对版本。启动不会生成图片，单纯刷新/查询不应调用模型。日志不能公开分享未经脱敏的内容。

升级前先等待当前任务完成，备份数据和配置，记录当前 Git 提交。然后拉取已验证版本，运行 `docker compose up -d --build`。数据卷保持不变。应用升级失败时恢复之前的提交再构建；如未来存在数据格式迁移，必须结合对应版本的备份恢复，不能仅切代码。

不要执行 `docker compose down -v`：它会删除数据卷。普通 `down` 不删除命名卷。服务器迁移时应同时迁移数据、密钥文件、.env 和预算配置；配置/密钥采用受控通道，不能进仓库。

## 备份

进入维护时段，确认没有任务生成中，再执行 `sh scripts/backup.sh`。脚本短暂停服务，导出所有业务数据卷及 SQLite 文件，完成后恢复服务。备份含用户图、提示词和用量，权限为私有，另存到服务器之外。备份 ZIP/TAR 不上传代码仓库。

单独备份 `secrets/`、`.env`、`deploy/budget.json`，与数据备份分开保管。Caddy 证书卷未纳入业务备份；正常域名网络下可重新签发，频繁重建可能触发签发频率限制。

## 恢复

先在独立服务器/项目名中演练。获取相同提交代码并完成 setup；不要启动正式服务，先将可信的备份解压到空的数据卷。脚本 `scripts/restore.py` 在容器中运行，拒绝绝对路径、父路径、软链接和硬链接，只允许四类业务路径和 usage。

```sh
docker compose stop
docker compose run --rm --no-deps -T --entrypoint python3 app scripts/restore.py < backups/data-TIMESTAMP.tar.gz
docker compose up -d
docker compose exec app python3 deploy/healthcheck.py
```

恢复脚本要求目标业务目录为空，避免旧新文件混合。已有数据时不要为了执行恢复直接清空：先另做备份，并使用新项目/新数据卷。恢复后人工核对图片数量和用量；未完成任务不会自动重发。

## 额度

系统统一采用 budget.json 的时区按日/月切换，不依赖服务器默认时区。默认洛杉矶日期。修改历史记录可能破坏额度准确性，不通过 SQL 人工删除失败预留；需要未来管理模块提供有审计记录的调整流程。

预留记录不是供应商账单，模型错误也可能产生费用。实际支出以 Google 项目账单为准，且存在时间延迟。不能承诺本系统阻止同一密钥在其他应用中的支出。
