# 部署到 R68S 软路由（OpenWrt，ARMv8/arm64）

适用：R68S（RK3568，arm64）+ OpenWrt + Docker，PS5/Portal 都接在这台路由的 LAN 口下。
路由器本身就是中继主机：PS5/Portal 的流量本来就从它走，让它兼任"码率中继"非常合适。

> 本文用**纯 `docker run` 命令**（不依赖 docker-compose，OpenWrt 上不一定有）。
> 如果你在 OpenWrt 上装了 `docker-compose`，也可以直接用包里的 `docker-compose.yml`。
> 命令中的 IP（192.168.1.x）为**示例**，请按你的网络修改。

## 1. 安装 Docker

SSH 登录 R68S：

```bash
opkg update
opkg install dockerd docker
# 可选：Web 界面管理
# opkg install luci-app-docker
/etc/init.d/dockerd enable
/etc/init.d/dockerd start
docker version
```

**存储提醒**：R68S 的 eMMC 空间有限，镜像约 200-300MB。先看空间：

```bash
df -h /
docker info | grep -i "docker root"
```

如果剩余空间紧张，把 Docker 数据目录挪到 U 盘/扩展分区
（在 `/etc/config/dockerd` 里调整 `data_root`，以该文件内注释为准），或先做 extroot。

**拉基础镜像慢**：可在 Docker 里配置国内镜像加速（`/etc/docker/daemon.json` 加
`registry-mirrors`，或 Luci 界面设置），然后重启 dockerd。

## 2. 确认 LAN 网桥（父接口）

```bash
ip -br addr
```

R68S 作为主路由时，LAN 侧网桥一般是 **`br-lan`**（LAN 口都桥接在它下面）。
中继容器就挂在这个桥上，与 PS5/Portal 同一二层。

也可以跑一遍环境自检：

```bash
cd /opt/ps5-portal-relay-docker   # 你上传部署包的目录
bash scripts/net-check.sh
```

## 3. 上传部署包并构建镜像（arm64）

把 `ps5-portal-relay-docker` 文件夹传到 R68S（scp 或 WinSCP），然后：

```bash
cd /opt/ps5-portal-relay-docker
# 国内网络建议加 pip 镜像源，避免构建时拉取 scapy 失败：
docker build --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple -t portal-relay:local .
```

构建会自动跑上游单元测试，失败会中断。R68S 上构建约几分钟。

## 4. 创建 macvlan 网络

```bash
docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  -o parent=br-lan \
  portal-lan
```

（把网段/网关换成你的；`RELAY_IP` 用 DHCP 池外的地址，如 192.168.1.215。）

## 5. 注册设备（configure-env）

保持 **PS5 和 Portal 开机唤醒**：

```bash
mkdir -p /opt/portal-relay
docker run --rm -it \
  --network portal-lan --ip 192.168.1.215 \
  --sysctl net.ipv4.ip_forward=0 \
  --cap-add NET_RAW --init --tmpfs /run \
  -v /opt/portal-relay/config:/etc/portal-bitrate \
  -v /opt/portal-relay/runtime:/var/lib/portal-bitrate-auto \
  -e PS5_IP=192.168.1.60 -e PORTAL_IP=192.168.1.50 -e PROFILE=65 \
  portal-relay:local configure-env
```

成功后会显示两台设备的 MAC。

## 6. 基线测试（baseline，约 60 秒）

**先把 Portal 从 PS5 断开**：

```bash
docker run --rm -it \
  --network portal-lan --ip 192.168.1.215 \
  --sysctl net.ipv4.ip_forward=0 \
  --cap-add NET_RAW --init --tmpfs /run \
  -v /opt/portal-relay/config:/etc/portal-bitrate \
  -v /opt/portal-relay/runtime:/var/lib/portal-bitrate-auto \
  portal-relay:local baseline
```

看到 `BASELINE READY` 后，**在 Portal 上连接 PS5**，保持约 60 秒，检查画面/手柄正常。

> 如果连接后日志里的 `forwarded_out` 一直不动，把 Portal **长按电源完全关机、等十几秒再开机**
> 后重连——社区反馈 Portal 的 ARP 缓存很固执，只在 Remote Play 里断开重连可能不够（上游 issue #2）。

## 7. 前台试验（try）

Portal 断开连接后：

```bash
docker run --rm -it \
  --network portal-lan --ip 192.168.1.215 \
  --sysctl net.ipv4.ip_forward=0 \
  --cap-add NET_RAW --init --tmpfs /run \
  -v /opt/portal-relay/config:/etc/portal-bitrate \
  -v /opt/portal-relay/runtime:/var/lib/portal-bitrate-auto \
  portal-relay:local try
```

看到 `AUTO READY` 后连接 Portal。**之后终端不会再输出任何内容是正常的**——上游的
成功日志只写文件、不打印终端。另开一个终端验证：
`tail -F /opt/portal-relay/runtime/status.json`（`forwarded_out` 持续上涨、
`unique_modified_startups` > 0 即已在修改码率），或
`tail -f /opt/portal-relay/runtime/events.log`（实时显示 `Startup modified, profile=65`）。
Portal 网络信息里目标码率提升即最终成功。**Ctrl+C** 停止（自动修复 Portal 的 ARP）。

> 同理：若重连后没有效果，先把 Portal 完全关机再开机，然后连接（见上文说明）。

## 8. 常驻模式

```bash
docker run -d --name portal-relay \
  --network portal-lan --ip 192.168.1.215 \
  --sysctl net.ipv4.ip_forward=0 \
  --cap-add NET_RAW --init --tmpfs /run \
  -v /opt/portal-relay/config:/etc/portal-bitrate \
  -v /opt/portal-relay/runtime:/var/lib/portal-bitrate-auto \
  --restart unless-stopped \
  portal-relay:local

docker logs -f portal-relay
```

之后每次玩，直接在 Portal 上连接 PS5 即可。
开机自启：`restart: unless-stopped` + `/etc/init.d/dockerd enable` 已设置，
路由器重启后自动恢复。

## 9. 停止/切换档位（重要）

**停止务必用优雅停止**（给守护进程留出修复 Portal ARP 的时间，至少 60 秒）：

```bash
docker stop -t 60 portal-relay && docker rm portal-relay
```

> ⚠️ 不要用 `docker rm -f`！那是立即 SIGKILL，Portal 的 ARP 表会指向失效的 MAC，
> 之后几分钟内 Portal 连不上 PS5（把 Portal 断开重连可立即恢复）。

切换码率档位（65/100/200）：先按上面停止，然后重跑第 5 步（configure-env，
把 `PROFILE` 换成新档位）和第 6 步（baseline），最后重新常驻。

## 10. R68S / OpenWrt 专项排障

**Portal 被重定向但 `forwarded_out` 一直为 0（Portal 能连但没数据）**
按下面顺序排查：

1. **先确认 Portal 是否真的跟随了重定向**（最常见原因）。社区反馈（上游 issue #2）：
   Portal 的 ARP 缓存很"固执"，在 Remote Play 里断开重连往往不够，需要
   **长按电源键把 Portal 完全关机，等十几秒再开机**，然后再连接 PS5。
2. **看帧到底有没有进容器**（在常驻容器里诊断）：
   ```bash
   # 临时装 tcpdump（诊断用，容器重建后失效）
   docker exec portal-relay apk add --no-cache tcpdump
   # 把 aa:bb:cc:dd:ee:50 换成 Portal 的 MAC（见 data/config/auto-config.json）
   docker exec portal-relay tcpdump -i eth0 -c 20 -e ether src aa:bb:cc:dd:ee:50
   ```
   - tcpdump **看不到** Portal 的帧 → 重定向没生效（Portal 没跟随 ARP），回到第 1 步；
   - tcpdump **看得到**但计数不动 → 继续第 3、4 步。
3. **桥接流量被 iptables 拦截**。Docker 会把主机 FORWARD 策略设为 DROP；
   若 `br_netfilter` 的挂钩开关打开，二层桥接帧也会过 FORWARD 链：

```bash
ls /sys/module/br_netfilter 2>/dev/null               # 有输出 = 模块已加载
cat /proc/sys/net/bridge/bridge-nf-call-iptables      # 关键开关：0=不过iptables 1=过
```

**注意：模块已加载 ≠ 一定拦截，真正的开关是 `bridge-nf-call-iptables`。**

- 若为 **0**：无需任何处理，直接继续排查其他原因；
- 若为 **1**：
  - 方案 A（推荐）：`sysctl -w net.bridge.bridge-nf-call-iptables=0`。
    只影响"同一桥内转发的帧"，路由/NAT 流量（其他容器上网等）不受影响；
    重启后可能被重新打开，持久化方法：
    `echo 'sysctl -w net.bridge.bridge-nf-call-iptables=0' >> /etc/firewall.user`
  - 方案 B（精准放行，仅这对设备、仅 LAN 桥）：
  ```bash
  iptables -I FORWARD -i br-lan -o br-lan -s 192.168.1.50 -d 192.168.1.60 -j ACCEPT
  iptables -I FORWARD -i br-lan -o br-lan -s 192.168.1.60 -d 192.168.1.50 -j ACCEPT
  ```
  （IP 换成你的 Portal/PS5；重启防火墙后需重设，可放进 `/etc/firewall.user`。）
  - 方案 C（最后手段）：`rmmod br_netfilter`（提示被占用说明有规则依赖它，回到方案 A/B）。

4. **macvlan 挂在 br-lan 上收包异常**：上游 issue #2 有用户在 OpenWrt 桥接接口上
   遇到"scapy socket 收不到、tcpdump 能收到"的情况。我们的容器里 socket 绑定的是
   macvlan 的 `eth0` 而不是 `br-lan`，正常不受此问题影响；若第 2 步确认
   "tcpdump 看得到、relay 计数不动"，即命中该问题——需要等上游把 Linux 接收路径
   改成原生 AF_PACKET，或按上游 AUTOMATION.md 在路由器上原生部署（需自行处理
   ip_forward 检查）。

**macvlan 创建失败**：确认父接口是 `br-lan`（不是 `lan` 这个逻辑接口名），
且内核有 macvlan 支持（新内核一般内建）。

**容器起来就退出、日志提示 IPv4 forwarding is enabled**：
确认 `docker run` 带了 `--sysctl net.ipv4.ip_forward=0`
（它只作用于容器网络命名空间，不影响路由器的转发功能，路由器照常上网）。

**R68S 上同时跑别的服务**：中继只对 PS5/Portal 这一对设备做 ARP 应答，
不影响其他设备；但它会 7×24 常驻监听（CPU 占用很低，RK3568 无压力）。

**升级**：重新上传覆盖文件夹 → 重新 `docker build` → 停止旧容器 →
重新常驻。注意上游代码变化会使基线失效，需重跑 configure-env + baseline。
