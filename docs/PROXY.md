# 车灯生图反代版

这是用户已验收的 Cockpit 反代版。源树是精确提交 `c5d62b9b533da6539e5c71ffbd4dbaab8338d0e9`，包含密钥生命周期修复 `8e437068134a3623f59b2b37db69112d29657cbb`。四个模块的生图请求发到 OpenAI 兼容的 Images API。页面布局、选项、规则提示词、准备校验、预算预留、失败不退还、自动重试 0 次和人工重试都保持原样。

不要把它和旧的 Google 版目录或数据卷混用。每人使用自己的 Cockpit 和自己的 API 配置。`127.0.0.1` 不能跨电脑共享。配置不在网页上；`scripts/setup-proxy.py` 隐藏输入密钥。`secrets/` 禁止上传。私有仓库要给别人用时，添加协作者，或提供不含密钥的离线源码包。

验证范围只按本系统记录：用户已在 macOS 验收；Linux 自动测试 130 项、`scripts/linux_smoke.py` 和源分支 CI 通过。Windows 当前没有验证，不能保证直接运行。不要套用其他项目的跨平台结论。

预算数字仍是原来的保守预留（参考 0.26、替换 0.27、套图每张 0.50、精修 0.50 美元）。它们是本系统防止重复支出的预留，**不是** Cockpit 或供应商账单，也不是反代的实际费用。失败后不自动重试；需要人在页面上再次提交。预留不会因为失败就自动变成已退款。

`gpt-image-2.6` 只是配置示例，不保证你的反代一定提供这个 id。不要填写 `sunburst` 或 `flare` 之类没有检测过的名字。

## 同事怎么配置

1. 用这个分支的源码，不要在 Google 版目录里改。
2. 安装运行依赖：Python 3.12、Ruby、nginx、curl，以及 `Pillow==11.3.0`。系统包可以按仓库 `Dockerfile` 里的列表安装（含 tesseract）。
3. 复制模板并填写，密钥不要发到聊天或 git：

```sh
mkdir -p secrets
cp deploy/image-proxy.example.json secrets/image-proxy.json
chmod 600 secrets/image-proxy.json
```

编辑 `secrets/image-proxy.json`：

- `baseUrl`：本机 Cockpit 用 `http://127.0.0.1:62037/v1`。只有 `127.0.0.1`、`localhost`、`::1` 允许 http。其他地址必须是 `https://`，否则启动直接失败。
- `apiKey`：反代密钥。文件权限保持 600。
- `model`：先可写成示例 `gpt-image-2.6`。

也可以运行 `python3 scripts/setup-proxy.py`，按中文提示隐藏输入密钥。它只写 `secrets/image-proxy.json`，不会动 `secrets/gemini_key` 或原来的 `.env`。

4. 只读检测模型，不生图：

```sh
python3 scripts/detect-image-model.py
```

把打印出来、你确认要用的 id 写回 `model`。检测失败不会改配置，也不会调用生图接口。

5. 先看四个原界面，不需要密钥，也不会生图：

```sh
python3 scripts/preview-ui.py
```

浏览器打开它打印的 `http://127.0.0.1:18080`。这是准备模式：01/02 用工作台原来的 `--mock`，03/04 页面能打开但生成保持未连接，不会生图。左上角 PictureOps 品牌区链回这个地址上的模块选择页（工作台 `#home`）。点击只做页面导航，不调用生成、重试或清空任务。01/02 在同一页内回到选择页，服务端正在跑的任务不会被这次点击取消。准备模式需要本机有 Python、Ruby 和 Pillow，不需要 nginx 或 tesseract。端口 8774、8775、8776、18080 被占用时会直接失败。

6. 真实模式才把生图指到你自己的 Cockpit。另一台电脑不能使用你的 `127.0.0.1`：

```sh
python3 scripts/run-proxy.py
```

浏览器打开 `http://127.0.0.1:18080`。这个进程就在本机网络里，所以能访问 `127.0.0.1:62037`。它只绑定本机 18080，不监听公网，不占用 Google 版的 80/443。

## 为什么不能把原版 Docker 直接指到 127.0.0.1

Google 版容器里的 `127.0.0.1` 是容器自己，不是宿主机上的 Cockpit。本反代版不用那套容器网络去访问 Cockpit。

- 同一台机器：用上面的 `run-proxy.py`。
- 必须用 Docker，并且是 Linux、Cockpit 也在这台 Linux 上：`docker compose -f compose.proxy.yaml up -d --build`。这个文件使用宿主机网络，镜像名是 `car-light-proxy:1.0.0-proxy.1`，数据卷名以 `car-light-proxy` 开头，站点只绑 `127.0.0.1:18080`。不要改成 `0.0.0.0`，那会把工作台暴露到局域网。
- `run-proxy.py` 会调用 PATH 里的 `nginx` 和 `ruby`，镜像请求再找 PATH 里的 `curl`。Linux 和本仓库的 Docker 镜像里有这些命令。用户已在自己的 macOS 上验收本版；这不表示每一台 Mac 都已经装好 nginx 和 Ruby。Windows 当前没有验证，不能保证直接运行，也不要套用其他项目的跨平台结论。不要把 Cockpit 端口公布到公网。
- Cockpit 在另一台机器：`baseUrl` 填那台机器的 `https://` 地址。本系统不会帮你做公网端口转发。

## 请求里实际发送什么

有参考图时：`POST {baseUrl}/images/edits`，multipart，字段只有 `model`、`prompt`、`size` 和按顺序重复的 `image[]`。02 先参考图、后产品图，角色说明留在提示词里。

03 某一张没有产品图时：`POST {baseUrl}/images/generations`，JSON，只有 `model`、`prompt`，以及比例对应的 `size`。

不发送 `quality`、`moderation`、`output_format`、`n`、`response_format`。这些没有作为必要参数验证过。

`size` 按页面上选中的原比例各自计算，不把 4:5、3:4、9:16 收成同一个竖图尺寸。默认长边取 1008，宽和高都取 16 的倍数。这样 4:5 是 `800x1008`，和先前项目实测过、接近 4:5 的尺寸一致。3:4 是 `752x1008`，4:3 是 `1008x752`，其余比例也各自不同。12:15 与 4:5 是同一个比例，冻结规则本来就会写成 4:5，所以请求尺寸相同。

这只说明请求里会带上接近原比例的尺寸。没有对当前 Cockpit 逐个比例重新打过生图接口，不能写成返回图必然就是这个像素。返回的字节原样保存，不裁切、不拉伸。若某个比例被反代拒绝，会停在这一次，不会偷偷换成另外三档。

要改某一档，在配置里加 `sizes`，例如 `"4:5": "640x800"`。宽和高必须是 16 的正倍数，并且不能偏离该比例太多；偏离过大的值会在启动或读取配置时失败。

提示词仍保留冻结规则里的原比例。准备阶段仍可能显示旧的原生像素说明，那是冻结记录，不是结果图已被验证为 2K。

03 的 WebP 会先解码再写成 PNG 后发送。只改 MIME 不算转换。01、02、04 本来就只收 JPEG/PNG。

响应里如果只有图片 URL，直接失败，不会去下载。自动重试始终是 0 次。超时视为远端结果未知。

安全类错误会显示为内容未通过检查并停止。计费失败不再指向 Google AI Studio。

## 2026-11-20 密钥生命周期修复

Mac 真实验收里，03 套图第一张返回 200，第二张和随后的人工重试都在十几毫秒内返回 401。同一密钥新开进程去读 `/models` 仍是 200，01/02 每次新进程也能连续成功。

代码核对结果：`deploy/image_proxy.py` 的 `execute()` 在 `finally` 里执行了 `config.api_key = None`。03 和 04 的进程会一直复用同一个 `Config`，所以第一次成功之后密钥被清掉，下一次请求带着空密钥立刻 401。01/02 每次由 Ruby 新开 Python 进程，从配置文件重新读取密钥，因此不受影响。这不是 Cockpit 拒钥，也没有对真实接口再发请求来验证。

修复后，同一次进程里的 `Config` 在成功或模拟错误之后都保留密钥。密钥是 `None`、空字符串或空白时，在打开网络之前就失败。失败诊断只保留整数 `httpStatus` 和 `edits`/`generations` 这两种 `endpointKind`，不保存密钥、提示词、图片或原始错误正文。自动重试仍是 0。

离线回归用占位密钥和本机假 HTTP 服务：同一配置连续两次成功、先 401 再成功，以及 03 连续两张、04 连续两次生成。没有访问真实 Cockpit。

另外，发行包里的 `deploy/image_probe.py` 以前是 `0644`，Ruby 会直接执行它，Mac 上出现过 Permission denied。仓库里的这个脚本现为可执行。业务规则没有因此改动。

## 和 Google 版隔离

| 项目 | Google 版 `main` | 本反代分支 |
|---|---|---|
| 编排文件 | `compose.yaml` | `compose.proxy.yaml` |
| 镜像 | `car-light-system:1.0.0-rc.1` | `car-light-proxy:1.0.0-proxy.1` |
| 密钥 | `secrets/gemini_key` | `secrets/image-proxy.json` |
| 站点 | 80/443 | 仅 `127.0.0.1:18080` |
| 数据卷 | 原卷名 | `car-light-proxy` 前缀 |

不要把两边的数据卷或密钥文件混用。
