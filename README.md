# PS5 Portal High Bitrate — Docker

> Pack the experimental [PS5 Remote Play high-bitrate][upstream] tool from
> [@atameric][upstream-author] into a ready-to-deploy Docker image that runs
> on always-on devices (NAS, OpenWrt router, any Linux host with Docker) —
> no need to keep a Mac/Windows PC running anymore.

[English](#whats-this) | [简体中文](#这是什么)

---

## What's this?

把 [atameric/ps5-portal-high-bitrate][upstream] 的实验性「PS5 Remote Play 高码率」工具打包成**开箱即用的 Docker 镜像**，跑在 7×24 开机的设备上（飞牛 NAS / OpenWrt 软路由 / 任何有 Docker 的 Linux 主机），不再需要 Mac/Windows 电脑一直开着。

This is a **Docker packaging layer** around [@atameric][upstream-author]'s
upstream Python tool. The upstream codebase is bundled **unmodified** under
`src/` (commit `97880a2e`) so the upstream baseline fingerprint stays valid;
this repo only adds the Dockerfile, the non-interactive `configure-env` entry
point, multi-arch CI, and Chinese docs.

### Why a separate repo?

Upstream ships an experimental Docker setup under `deploy/docker/` that's
hard to use as-is on consumer routers/NAS:

- Multi-arch image build is not configured (you'd have to build on-device)
- No non-interactive enrollment flow — interactive setup is painful on headless hosts
- No community gotchas documented (the well-known [issue #2][issue2] ARP cache trap, etc.)
- Path leakage from Windows checkouts (CRLF in shell scripts trips `ash`)

This repo fixes that. Upstream code itself is untouched — when upstream
bumps, you `cp` the new `src/` in and rebuild.

[upstream]: https://github.com/atameric/ps5-portal-high-bitrate
[upstream-author]: https://github.com/atameric
[issue2]: https://github.com/atameric/ps5-portal-high-bitrate/issues/2

### ⚠️ Experimental disclaimer

- This is **not** jailbreak, **not** 4K unlock, **not** latency reduction.
- Only verified on Portal firmware **7.1.7**. Other firmwares may not work.
- The tool XORs the `target bitrate` field inside the Portal→PS5 handshake
  packet (`25000` → `65000` / `100000` / `200000`). It does **not** touch
  resolution. The video stream still goes PS5→Portal **directly**; the
  container only relays the Portal→PS5 control direction.

---

## 这是？

[atameric/ps5-portal-high-bitrate][upstream] 的「PS5 Remote Play 高码率」工具的 **Docker 部署包装**，跑在 7×24 开机的设备上（飞牛 NAS / OpenWrt 软路由 / 任何有 Docker 的 Linux），不再需要 Mac/Windows 电脑一直开着。

这个仓库**只做 Docker 层**（Dockerfile、非交互 `configure-env`、多架构 CI、中文文档），上游 Python 代码以 `src/` 形式原样打包（commit `97880a2e`），保持基线指纹一致，上游更新时直接替换 `src/` 重新构建即可。

> ⚠️ **实验性声明**：这不是越狱、不是 4K 解锁、不保证降低延迟。仅在 Portal 固件 **7.1.7** 上验证过。
> 工具只是把 Portal→PS5 握手包里的"目标码率"字段从 `25000` 改成 `65000`/`100000`/`200000`，不改分辨率；
> 视频流仍然走 PS5→Portal 直连，不经过本容器。

### 为什么单开仓库？

上游自带的 `deploy/docker/` 实验方案在 NAS / 软路由场景不好用：

- 没配置多架构构建，用户得在设备本地编译（ARM 路由器编译又慢又挤存储）
- 没有非交互注册流程，无头设备跑交互式注册很痛苦
- 没记社区踩坑（[issue #2][issue2] 那个 Portal ARP 缓存顽固、需要完全关机重启才跟随重定向的事）
- 从 Windows 签出的代码上下文带 CRLF，会让 `ash` 执行 `set -eu\r` 时报 `illegal option -`

本仓库解决这些。上游代码本身一字未改，指纹绑定不受影响。

---

## Quick start

```bash
git clone https://github.com/<your-gh-user>/ps5-portal-high-bitrate-docker.git
cd ps5-portal-high-bitrate-docker
cp .env.example .env && vi .env   # set LAN_PARENT, SUBNET, GATEWAY, RELAY_IP, PS5_IP, PORTAL_IP

bash scripts/build.sh             # build for current arch (runs unit tests inside)
docker network create -d macvlan --subnet ${SUBNET} --gateway ${GATEWAY} -o parent=${LAN_PARENT} portal-lan

# register: keep PS5 & Portal awake
docker run --rm -it --network portal-lan --ip ${RELAY_IP} \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  --env PS5_IP=... --env PORTAL_IP=... --env PROFILE=65 \
  ps5-portal-relay:local configure-env
docker run --rm -it --network portal-lan --ip ${RELAY_IP} \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  ps5-portal-relay:local baseline   # see BASELINE READY, then connect from Portal for ~60s

docker run -d --name portal-relay --network portal-lan --ip ${RELAY_IP} \
  --sysctl net.ipv4.ip_forward=0 --cap-add NET_RAW --init --tmpfs /run \
  --restart unless-stopped ps5-portal-relay:local
```

Or, if you'd rather pull a prebuilt multi-arch image instead of building:

```bash
docker pull ghcr.io/<your-gh-user>/ps5-portal-relay:latest
# tag it as ps5-portal-relay:local and use the same commands above
```

Prebuilt images are published automatically on tag pushes (see `.github/workflows/release.yml`).

## How it works (30 seconds)

1. The container answers ARP for the PS5 (only for the Portal→PS5 pair, one-way), inserting itself between them;
2. It watches new Portal→PS5 handshakes, XORs the bitrate field at base64 offset 334 so PS5 opens a higher-bitrate session;
3. After modification the PS5→Portal video stream still goes **direct**, the relay only forwards Portal→PS5 control/input and runs a watchdog that auto-repairs Portal's ARP on graceful exit.

Because step 1 requires L2 traffic to/from the devices, the container needs **its own MAC+IP in the same L2 broadcast domain** — that's why we use a **macvlan** network, not the default bridge/NAT.

## Deployment guides

- [`docs/飞牛NAS-X86-部署.md`](docs/飞牛NAS-X86-部署.md) — 飞牛 NAS（X86/amd64，fnOS），带 GUI 步骤
- [`docs/OpenWrt-R68S-ARM64-部署.md`](docs/OpenWrt-R68S-ARM64-部署.md) — R68S / OpenWrt 软路由（arm64），纯 `docker run` 命令
- [`docs/日常使用与排障.md`](docs/日常使用与排障.md) — 每次玩的流程 + 故障对照表 + 社区反馈

英文用户：read the [Quick start](#quick-start) above and [`docs/OpenWrt-R68S-ARM64-部署.md`](docs/OpenWrt-R68S-ARM64-部署.md) — the `docker run` commands work anywhere with Docker; the IP values are placeholders.

## Directory layout

```
├── Dockerfile               # Alpine + Python + scapy, multi-arch
├── docker-compose.yml       # macvlan network + service definition
├── .env.example             # configuration template
├── .github/workflows/
│   └── release.yml          # multi-arch build → ghcr.io on tag push
├── docker/
│   ├── docker_configure.py  # non-interactive enrollment (configure-env)
│   └── portal-docker        # entrypoint wrapper (forwards other cmds to upstream `portal`)
├── src/                     # upstream Python source, unmodified (incl. tests/, deploy/)
├── scripts/
│   ├── build.sh             # local build + in-image tests
│   ├── buildx-multiarch.sh  # local multi-arch build (when you can't wait for CI)
│   └── net-check.sh         # pre-deploy host environment check
└── docs/                    # Chinese deployment & troubleshooting docs
```

## Multi-arch CI

Tag a release (`git tag v0.1.0 && git push --tags`) and the
[release workflow][.github/workflows/release.yml] will:

- Build `linux/amd64` + `linux/arm64` with `docker/buildx` + QEMU
- Push to `ghcr.io/<owner>/ps5-portal-relay:{latest, <tag>}`
- Use build cache via `gha` for fast rebuilds

To run the same build locally:

```bash
bash scripts/buildx-multiarch.sh   # see header for required env vars
```

[.github/workflows/release.yml]: .github/workflows/release.yml

## Acknowledgements

- All credit for the underlying technique goes to **[@atameric][upstream-author]** —
  go star [the upstream repo][upstream].
- Community folk in [upstream issue #2][issue2] shared real-world deployment pain
  (especially around Portal's stubborn ARP cache and `br_netfilter` interaction),
  much of which shaped this repo's troubleshooting guide.

## License

[MIT](LICENSE). The `src/` directory contains upstream code that is also MIT-licensed;
all changes to upstream code are limited to packaging (Dockerfile / scripts / docs), and
the upstream Python files themselves are bundled **unmodified**.