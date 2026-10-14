# PS5 Portal High Bitrate — Docker

**语言 / Language**：[简体中文](#简体中文) · [English](#english)

---

## 简体中文

### 这是什么

把 [atameric/ps5-portal-high-bitrate](https://github.com/atameric/ps5-portal-high-bitrate) 的实验性「PS5 Remote Play 高码率」工具打包成**开箱即用的 Docker 镜像**，跑在 7×24 开机的设备上（飞牛 NAS / OpenWrt 软路由 / 任何有 Docker 的 Linux 主机），不再需要 Mac/Windows 电脑一直开着。

本仓库**只做 Docker 层**：上游 Python 代码以 `src/` 形式原样打包（commit `97880a2e`，一字未改，基线指纹保持有效），外加 Dockerfile、非交互 `configure-env` 入口、多架构 CI 和中文文档。上游更新时直接替换 `src/` 重新构建即可。

> ⚠️ **实验性声明**：这不是越狱、不是 4K 解锁、不保证降低延迟。仅在 Portal 固件 **7.1.7** 上验证过。
> 工具只把 Portal→PS5 握手包里的"目标码率"字段从 `25000` 改成 `65000`/`100000`/`200000`，不改分辨率；
> 视频流仍然走 PS5→Portal 直连，不经过本容器。

### 工作原理（30 秒）

1. 容器对 PS5 做**单向 ARP 应答**（仅 Portal→PS5 这一对设备），把自己插入到二者之间；
2. 监听新的 Portal→PS5 握手包，XOR 修改 base64 偏移 334 处的码率字段，PS5 便以更高速率开会话；
3. 修改后视频流仍然 PS5→Portal **直连**，容器只转发 Portal→PS5 的控制/输入方向；优雅退出时自动修复 Portal 的 ARP 表。

因为第 1 步需要收发二层帧，容器必须在同一广播域内拥有**自己的 MAC + IP**——所以用 **macvlan** 网络，Docker 默认的 bridge/NAT 无法工作。

### 快速开始

前置条件：Docker 主机与 PS5/Portal 在同一局域网；PS5 和 Portal 保持开机（不能待机）。

```bash
# —— 0. 按你的网络修改下面几个值（下面是常见家用网段示例）——
LAN_PARENT=br-lan           # 连 LAN 的网卡：OpenWrt 填 br-lan；飞牛NAS 填 enp2s0/bond0 等（Wi-Fi 不行）
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
RELAY_IP=192.168.1.215      # 中继容器 IP：须在 DHCP 池之外，或在 DHCP 里做保留
PS5_IP=192.168.1.60
PORTAL_IP=192.168.1.50
PROFILE=65                  # 码率档位：65 / 100 / 200（200 为实验性，建议先用 65）

# —— 1. 创建 macvlan 网络 ——
docker network create -d macvlan \
  --subnet $LAN_SUBNET --gateway $LAN_GATEWAY \
  -o parent=$LAN_PARENT portal-lan

# —— 2. 获取镜像（二选一）——
# 2a. 拉预构建镜像（自动匹配 amd64 / arm64，推荐）
docker pull ghcr.io/shawnzhou1993/portal-relay:latest
docker tag ghcr.io/shawnzhou1993/portal-relay:latest portal-relay:local
# 2b. 或本地构建（构建过程内置上游 37 项单元测试，失败会中断）：
#   git clone https://github.com/ShawnZhou1993/ps5-portal-high-bitrate-docker.git
#   cd ps5-portal-high-bitrate-docker && bash scripts/build.sh

# —— 3. 注册（解析 PS5/Portal 的 MAC，写入本地配置）——
mkdir -p data/config data/runtime
docker run --rm -it --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  -e PS5_IP=$PS5_IP -e PORTAL_IP=$PORTAL_IP -e PROFILE=$PROFILE \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local configure-env

# —— 4. 基线透传测试：看到 BASELINE READY 后，从 Portal 连接 PS5，保持约 60 秒 ——
docker run --rm -it --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local baseline

# —— 5.（建议）前台试验：看到 AUTO READY 后连接 Portal。之后终端不再输出是正常的 ——
#        （上游成功日志只写文件、不打印终端）。另开终端验证：
#        tail -F data/runtime/status.json   # forwarded_out 上涨、unique_modified_startups>0 即成功
#        tail -f data/runtime/events.log    # 实时显示 Startup modified, profile=65
docker run --rm -it --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local try

# —— 6. 常驻模式：之后每次玩，直接在 Portal 上连接 PS5 即可 ——
docker run -d --name portal-relay --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  --restart unless-stopped \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local
```

> **停止必须优雅**：用 `docker stop -t 60 portal-relay`（或 compose `down`）。`docker rm -f` 强杀会让 Portal 的 ARP 指向失效 MAC，几分钟连不上 PS5。
>
> **Portal 重连无效时**：长按电源键完全关机、等十几秒再开机（社区反馈：Remote Play 里断开重连不够，ARP 缓存顽固）。

有 docker compose 的环境也可以走 `.env` 流程：`cp .env.example .env` 改好参数后 `docker compose run --rm relay configure-env` → `baseline` → `try` → `up -d`。

### 平台与验证状态

| 平台 | 状态 |
|---|---|
| OpenWrt 软路由（R68S / arm64） | ✅ 全流程实机验证（注册 → 基线 → 65 档常驻） |
| 飞牛 NAS 等 X86/amd64 主机 | 🔶 镜像构建 + 镜像内单测已验证；运行时待实机确认 |
| 任何有 Docker 的 Linux | 🔶 同上；需内核支持 macvlan（主流发行版均内置） |

amd64 / arm64 镜像由 CI 同流程构建（含镜像内上游单元测试）；macvlan、NET_RAW、ip_forward 均为 Linux 内核能力，与 CPU 架构无关。目前完整的运行时验证记录在 arm64 平台。

### 详细文档

- [`docs/飞牛NAS-X86-部署.md`](docs/飞牛NAS-X86-部署.md) — 飞牛 NAS（fnOS，X86/amd64），含 GUI 步骤
- [`docs/OpenWrt-R68S-ARM64-部署.md`](docs/OpenWrt-R68S-ARM64-部署.md) — R68S / OpenWrt 软路由（arm64），纯 `docker run`
- [`docs/日常使用与排障.md`](docs/日常使用与排障.md) — 每次玩的流程、故障对照表、社区反馈（issue #2）处理

### 让 AI 助手帮你部署

本文档所有命令均可直接粘贴执行。如果卡住了，把本 README、`docs/` 下对应平台的文档，连同你的网络参数（局域网网段/网关、PS5/Portal/中继的 IP、Docker 主机的父网卡名）一起发给任何大模型（ChatGPT、Claude、各类 AI 编程助手等），即可获得针对你实际环境的下一步命令。排障时把终端的实际输出和 `data/runtime/status.json` 的内容一起发给它，效果最好。

### 目录结构

```
├── Dockerfile               # Alpine + Python + scapy，多架构；构建时自动去 CR 并跑单测
├── docker-compose.yml       # macvlan 网络 + 服务定义（有 compose 的环境可用）
├── .env.example             # 配置模板
├── .gitattributes           # 强制 LF（防止 Windows 签出触发 ash 的 CRLF 报错）
├── .github/workflows/
│   └── release.yml          # tag 推送 → 多架构构建 → ghcr.io
├── docker/
│   ├── docker_configure.py  # 非交互注册（configure-env）
│   └── portal-docker        # 入口包装（把其他子命令转发给上游 portal）
├── src/                     # 上游 Python 源码，原样未改（含 tests/ 与 deploy/）
├── scripts/
│   ├── build.sh             # 本地构建 + 镜像内测试
│   ├── buildx-multiarch.sh  # 本地多架构构建
│   └── net-check.sh         # 部署前宿主机环境检查
└── docs/                    # 中文部署与排障文档
```

### 多架构 CI

推 tag 即自动发布：`git tag v0.1.0 && git push --tags`，[release workflow](.github/workflows/release.yml) 会用 QEMU + buildx 构建 `linux/amd64` + `linux/arm64` 并推送到 `ghcr.io/shawnzhou1993/portal-relay`（标签：`v0.1.0` / `0.1.0` / `0.1` / `0` / `latest`）。本地手动多架构构建：`REGISTRY=ghcr.io/ShawnZhou1993 TAG=v0.1.0 bash scripts/buildx-multiarch.sh`。

### 致谢与 License

- 底层技术的全部功劳归 **[@atameric](https://github.com/atameric)**，请去给[上游仓库](https://github.com/atameric/ps5-portal-high-bitrate) 点 star。
- [上游 issue #2](https://github.com/atameric/ps5-portal-high-bitrate/issues/2) 里社区分享的真实部署经验（Portal ARP 缓存顽固、br_netfilter 交互等）塑造了本仓库的排障文档。

[MIT](LICENSE)。`src/` 内为上游代码（同为 MIT），上游 Python 文件**原样未改**，本仓库的改动仅限打包层（Dockerfile / 脚本 / 文档）。

---

## English

### What's this

A **Docker packaging layer** around [@atameric](https://github.com/atameric)'s experimental [PS5 Remote Play high-bitrate](https://github.com/atameric/ps5-portal-high-bitrate) tool, ready to deploy on always-on devices (fnOS NAS / OpenWrt router / any Linux host with Docker) — no need to keep a Mac/Windows PC running anymore.

This repo only adds the Docker layer: the upstream Python code is bundled **unmodified** under `src/` (commit `97880a2e`, baseline fingerprint stays valid), plus a Dockerfile, a non-interactive `configure-env` entry point, multi-arch CI, and Chinese docs. When upstream bumps, `cp` the new `src/` in and rebuild.

> ⚠️ **Experimental disclaimer**: this is **not** jailbreak, **not** 4K unlock, **not** latency reduction. Only verified on Portal firmware **7.1.7**.
> The tool XORs the `target bitrate` field inside the Portal→PS5 handshake packet (`25000` → `65000` / `100000` / `200000`). It does **not** touch resolution; the video stream still goes PS5→Portal **directly**.

### How it works (30 seconds)

1. The container answers ARP for the PS5 (only for the Portal→PS5 pair, one-way), inserting itself between them;
2. It watches new Portal→PS5 handshakes and XORs the bitrate field at base64 offset 334, so the PS5 opens a higher-bitrate session;
3. After modification the PS5→Portal video stream still goes **direct**; the container only relays the Portal→PS5 control/input direction and auto-repairs the Portal's ARP table on graceful exit.

Because step 1 requires L2 traffic to/from the devices, the container needs **its own MAC+IP in the same broadcast domain** — hence a **macvlan** network; Docker's default bridge/NAT cannot work.

### Quick start

Prerequisites: the Docker host shares the LAN with the PS5/Portal; keep both awake (not in rest mode).

```bash
# —— 0. Adjust these values for your network (common home subnet shown) ——
LAN_PARENT=br-lan           # NIC bridged to LAN: br-lan on OpenWrt; enp2s0/bond0 etc. on NAS (no Wi-Fi)
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
RELAY_IP=192.168.1.215      # relay container IP: outside the DHCP pool, or reserved in DHCP
PS5_IP=192.168.1.60
PORTAL_IP=192.168.1.50
PROFILE=65                  # bitrate profile: 65 / 100 / 200 (200 is experimental; start with 65)

# —— 1. Create the macvlan network ——
docker network create -d macvlan \
  --subnet $LAN_SUBNET --gateway $LAN_GATEWAY \
  -o parent=$LAN_PARENT portal-lan

# —— 2. Get the image (pick one) ——
# 2a. Pull the prebuilt image (auto-matches amd64 / arm64, recommended)
docker pull ghcr.io/shawnzhou1993/portal-relay:latest
docker tag ghcr.io/shawnzhou1993/portal-relay:latest portal-relay:local
# 2b. Or build locally (runs the upstream 37 unit tests inside the build; fails fast):
#   git clone https://github.com/ShawnZhou1993/ps5-portal-high-bitrate-docker.git
#   cd ps5-portal-high-bitrate-docker && bash scripts/build.sh

# —— 3. Enroll (resolves PS5/Portal MACs, writes local config) ——
mkdir -p data/config data/runtime
docker run --rm -it --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  -e PS5_IP=$PS5_IP -e PORTAL_IP=$PORTAL_IP -e PROFILE=$PROFILE \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local configure-env

# —— 4. Baseline passthrough test: at BASELINE READY, connect from the Portal for ~60s ——
docker run --rm -it --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local baseline

# —— 5. (Recommended) Foreground trial: at AUTO READY, connect the Portal. The ——
#        terminal then goes quiet (normal — upstream success logs only go to files).
#        Verify from another terminal:
#        tail -F data/runtime/status.json   # rising forwarded_out, unique_modified_startups>0 = working
#        tail -f data/runtime/events.log    # live: Startup modified, profile=65
docker run --rm -it --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local try

# —— 6. Resident mode: from now on, just connect from the Portal whenever you play ——
docker run -d --name portal-relay --network portal-lan --ip $RELAY_IP \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  --restart unless-stopped \
  -v "$PWD/data/config:/etc/portal-bitrate" \
  -v "$PWD/data/runtime:/var/lib/portal-bitrate-auto" \
  portal-relay:local
```

> **Always stop gracefully**: use `docker stop -t 60 portal-relay` (or compose `down`). `docker rm -f` leaves the Portal's ARP pointing at a dead MAC — the PS5 becomes unreachable from the Portal for minutes.
>
> **If reconnecting the Portal doesn't work**: fully power it off (hold the power button), wait ~15 seconds, power on again — community reports that disconnecting inside Remote Play is not enough (stubborn ARP cache).

With docker compose available, you can also use the `.env` flow: `cp .env.example .env`, edit the values, then `docker compose run --rm relay configure-env` → `baseline` → `try` → `up -d`.

### Platform & verification status

| Platform | Status |
|---|---|
| OpenWrt router (R68S / arm64) | ✅ Full runtime verified (enroll → baseline → 65 profile resident) |
| fnOS NAS and other X86/amd64 hosts | 🔶 Build + in-image unit tests verified; runtime pending field test |
| Any Linux host with Docker | 🔶 Same as above; requires kernel macvlan support (built into mainstream distros) |

Both amd64 and arm64 images are built by the same CI pipeline (including the in-image upstream unit tests); macvlan, NET_RAW and ip_forward are kernel capabilities independent of CPU architecture. Full runtime verification records so far are on arm64.

### Documentation

Chinese deployment & troubleshooting guides (the `docker run` commands are platform-agnostic; IP values are placeholders):

- [`docs/飞牛NAS-X86-部署.md`](docs/飞牛NAS-X86-部署.md) — fnOS NAS (X86/amd64) with GUI steps
- [`docs/OpenWrt-R68S-ARM64-部署.md`](docs/OpenWrt-R68S-ARM64-部署.md) — R68S / OpenWrt router (arm64), plain `docker run`
- [`docs/日常使用与排障.md`](docs/日常使用与排障.md) — play-session workflow, troubleshooting table, community findings (issue #2)

### Deploy with an AI assistant

Every command in this README is copy-paste ready. If you get stuck, feed this README plus the platform guide under `docs/` and your network parameters (subnet/gateway, PS5/Portal/relay IPs, parent NIC on the Docker host) to any LLM (ChatGPT, Claude, AI coding assistants, ...) and it will produce the next commands for your specific setup. For troubleshooting, include the actual terminal output and the contents of `data/runtime/status.json` for the best results.

### Directory layout

```
├── Dockerfile               # Alpine + Python + scapy, multi-arch; strips CR and runs tests at build time
├── docker-compose.yml       # macvlan network + service definition (for compose environments)
├── .env.example             # configuration template
├── .gitattributes           # enforces LF (prevents Windows-checkout CRLF from tripping ash)
├── .github/workflows/
│   └── release.yml          # tag push → multi-arch build → ghcr.io
├── docker/
│   ├── docker_configure.py  # non-interactive enrollment (configure-env)
│   └── portal-docker        # entrypoint wrapper (forwards other subcommands to upstream portal)
├── src/                     # upstream Python source, unmodified (incl. tests/ and deploy/)
├── scripts/
│   ├── build.sh             # local build + in-image tests
│   ├── buildx-multiarch.sh  # local multi-arch build
│   └── net-check.sh         # pre-deploy host environment check
└── docs/                    # Chinese deployment & troubleshooting docs
```

### Multi-arch CI

Push a tag to publish: `git tag v0.1.0 && git push --tags`. The [release workflow](.github/workflows/release.yml) builds `linux/amd64` + `linux/arm64` with QEMU + buildx and pushes to `ghcr.io/shawnzhou1993/portal-relay` (tags: `v0.1.0` / `0.1.0` / `0.1` / `0` / `latest`). Local multi-arch build: `REGISTRY=ghcr.io/ShawnZhou1993 TAG=v0.1.0 bash scripts/buildx-multiarch.sh`.

### Acknowledgements & License

- All credit for the underlying technique goes to **[@atameric](https://github.com/atameric) — please star [the upstream repo](https://github.com/atameric/ps5-portal-high-bitrate).
- Real-world deployment experience shared in [upstream issue #2](https://github.com/atameric/ps5-portal-high-bitrate/issues/2) (stubborn Portal ARP cache, br_netfilter interaction, etc.) shaped this repo's troubleshooting guide.

[MIT](LICENSE). `src/` contains upstream code (also MIT); the upstream Python files are bundled **unmodified**, and all changes in this repo are limited to packaging (Dockerfile / scripts / docs).
