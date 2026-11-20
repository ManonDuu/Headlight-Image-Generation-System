# 车灯生图系统 — Cockpit 反代版

这是已经验收的独立反代版，用来在本机把四个模块的生图请求发到你自己的 Cockpit。它不是 Google 版，也不要和旧的 `Manon-Private` 主线混用。

源树来自精确提交 `c5d62b9b533da6539e5c71ffbd4dbaab8338d0e9`，其中包含密钥生命周期修复 `8e437068134a3623f59b2b37db69112d29657cbb`。这个目录是新的干净副本，不带原来的 Git 历史。已去掉研究归档、内部研究、旧对照文件、真实密钥、真实配置和运行数据。规则、提示词、页面、测试和无密钥模板都保留。

详细行为和配置字段见 [docs/PROXY.md](docs/PROXY.md)。

## 哪些环境已经验证

- macOS：用户已在自己的 Mac 上验收这个反代版。
- Linux：源提交的自动测试是 130 项（104 项原模块测试 + 26 项部署/反代测试），`scripts/linux_smoke.py` 通过，该分支的 Linux CI 通过。发布前又在这份干净目录上重跑了同样的检查。
- Windows：当前没有做安装或运行验证，不能保证这些命令能直接运行。不要把其他项目的跨平台结论用到本系统。

## 每人使用自己的 Cockpit

每个人都要有自己电脑上的 Cockpit，以及自己的 API 配置。`127.0.0.1` 和 `localhost` 只指向正在操作的那一台电脑，不能把你的本机地址交给另一台电脑共用。

配置不写在网页里。`python3 scripts/setup-proxy.py` 用隐藏输入读取密钥，密钥不会出现在命令参数或页面上。`secrets/` 只留在本机，不要上传、不要提交、不要放进聊天。

这个仓库是私有的。要让别人使用，把对方加为协作者，或者交给对方一份不含 `secrets/` 的离线源码包。对方仍然要配置自己的 Cockpit。

## 两种启动方式

准备模式不需要密钥，也不会生图。01/02 使用原来的模拟模式，03/04 页面能打开，但生成保持未连接。

```sh
python3 -m pip install Pillow==11.3.0
python3 scripts/preview-ui.py
```

浏览器打开它打印的 `http://127.0.0.1:18080`。这一步需要本机有 Python 3.12、Ruby 和 Pillow。不需要 nginx。

真实模式才会连接你本机的 Cockpit：

```sh
mkdir -p secrets
cp deploy/image-proxy.example.json secrets/image-proxy.json
chmod 600 secrets/image-proxy.json
python3 scripts/setup-proxy.py
python3 scripts/detect-image-model.py
python3 scripts/run-proxy.py
```

浏览器打开 `http://127.0.0.1:18080`。真实模式还需要 PATH 里有 `nginx`、`ruby` 和 `curl`。它只监听本机 18080，不监听公网。`baseUrl` 在本机 Cockpit 上使用 `http://127.0.0.1:62037/v1`。

## 页面和失败后的操作

四个模块的左上角 PictureOps 品牌区都会回到模块选择页。经上面的入口，这个选择页就是 `http://127.0.0.1:18080/`。点击品牌区不会触发生成、自动重试或清空任务。

自动重试是 0 次。某张图失败后，由人在页面上再次提交；系统不会自己补发。

`deploy/budget.json` 里的金额是本系统记账用的保守预留，不是 Cockpit 或供应商账单。失败、超时和中断不会自动退还这笔预留。

## 不要上传的内容

不要上传 `secrets/`、真实 `.env`、真实 `image-proxy.json`、用户图片、任务数据库、用量日志或其他运行数据。仓库里的 `deploy/image-proxy.example.json` 和 `.env.example` 只是空模板。
