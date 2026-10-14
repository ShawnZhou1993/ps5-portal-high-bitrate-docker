# 部署到飞牛NAS（fnOS，X86/amd64）

适用：飞牛NAS（fnOS）+ Docker 应用，PS5/Portal 与 NAS 在同一有线局域网。

## 1. 前置准备

1. **开启 SSH**：fnOS 设置里打开 SSH 开关（默认关闭；不同版本可能在"系统设置/远程访问"里），
   用NAS登录密码通过 SSH 连接：
   ```bash
   ssh 你的NAS用户名@NAS的IP
   ```
2. **安装 Docker 应用**：在 fnOS 应用商店安装「Docker」，装好后 SSH 里应有 `docker` 命令：
   ```bash
   docker version
   ```
3. **上传部署包**：把 `ps5-portal-relay-docker` 整个文件夹传到 NAS
   （可用 SMB 共享文件夹，或在本机用 scp）：
   ```bash
   # 在本机（Windows PowerShell / Git Bash）执行
   scp -r ps5-portal-relay-docker 用户名@NAS的IP:~/
   ```

## 2. 确认父网卡（LAN_PARENT）

```bash
ip -br addr
```

- NAS 连接家庭局域网的那块**有线网卡**就是父网卡：可能是 `enp2s0`/`enp3s0` 等，
  如果你在 fnOS 里做了**多网口聚合**，则是 `bond0`；
- 如果 PS5/Portal 其实接在 NAS 的另一个网段/VLAN 后面，此方案不适用（要求同二层局域网）；
- Wi-Fi 网卡不能用作 macvlan 父接口。

也可以跑一遍环境自检：

```bash
cd ~/ps5-portal-relay-docker
bash scripts/net-check.sh
```

## 3. 修改配置

```bash
cd ~/ps5-portal-relay-docker
cp .env.example .env
vi .env
```

按你的网络填写（示例）：

```ini
LAN_PARENT=bond0                 # NAS 上接局域网的有线网卡/聚合口
LAN_SUBNET=192.168.1.0/24
LAN_GATEWAY=192.168.1.1
RELAY_IP=192.168.1.215           # DHCP 池之外的空闲地址
PS5_IP=192.168.1.60              # 建议在路由器里做 DHCP 保留
PORTAL_IP=192.168.1.50
PROFILE=65
IFACE=eth0                       # 容器内固定 eth0，不用改
```

## 4. 构建镜像（amd64）

```bash
bash scripts/build.sh
```

构建会自动执行上游单元测试，最后输出 `portal-relay:local`。
（首次构建需要拉取 Alpine 基础镜像和 scapy，耐心等几分钟。）

## 5. 注册设备（configure-env）

保持 **PS5 和 Portal 开机唤醒**，然后：

```bash
docker compose run --rm relay configure-env
```

成功后会显示两台设备的 MAC，并写入 `data/config/auto-config.json`。

## 6. 基线测试（baseline，约 60 秒）

**先把 Portal 从 PS5 断开**，然后：

```bash
docker compose run --rm relay baseline
```

看到 `BASELINE READY` 后，**在 Portal 上连接 PS5**，正常玩一会儿保持约 60 秒，
检查画面/手柄是否正常（这一步是透传，不改码率，只为确认链路通）。
结束后看到 `Baseline receipt` 相关输出即通过。

> 如果连接后日志计数（`forwarded_out`）一直不动，把 Portal **长按电源完全关机、等十几秒再开机**
> 后重连——社区反馈 Portal 的 ARP 缓存很固执，只在 Remote Play 里断开重连可能不够（上游 issue #2）。

## 7. 前台试验（try）

Portal 断开与 PS5 的连接，然后：

```bash
docker compose run --rm relay try
```

看到 `AUTO READY` 后连接 Portal，日志出现 `Startup modified` 说明启动包已修改；
在 Portal 的网络信息里观察目标码率是否提升。按 **Ctrl+C** 停止（会自动修复 ARP）。

> 若重连后没有效果，先把 Portal 完全关机再开机，然后连接（同上）。

## 8. 常驻模式

```bash
docker compose up -d
docker compose logs -f
```

之后**每次玩 PS5，直接在 Portal 上连接即可**，中继会自动捕获新握手并改码率。

开机自启：compose 已设置 `restart: unless-stopped`，只要 fnOS 的 Docker 应用开机启动
（默认即可），NAS 重启后容器会自动恢复。

## 9. 用 fnOS Docker 图形界面管理（可选）

推荐流程：SSH 里构建一次镜像后，日常用界面开关容器。

1. SSH 执行 `bash scripts/build.sh` 得到 `portal-relay:local`；
2. fnOS Docker 界面 → Compose → 新建项目，粘贴下面的 YAML
   （**把 IP 全部换成你的实际值**，界面方式不用 `.env`）：

```yaml
name: portal-relay
services:
  relay:
    image: portal-relay:local
    init: true
    restart: unless-stopped
    stop_grace_period: 60s
    cap_add: [NET_RAW]
    sysctls:
      net.ipv4.ip_forward: "0"
    tmpfs:
      - /run
    volumes:
      - ./data/config:/etc/portal-bitrate
      - ./data/runtime:/var/lib/portal-bitrate-auto
    networks:
      lan:
        ipv4_address: 192.168.1.215
networks:
  lan:
    driver: macvlan
    driver_opts:
      parent: bond0
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
```

注意：图形界面里做 `configure-env`/`baseline`/`try` 不方便（需要交互和看日志），
这三步仍建议用 SSH 的 `docker compose run --rm relay ...` 完成。

## 10. NAS 专项注意

- **多网卡**：只有连接 PS5/Portal 局域网的那块网卡（或 bond）能当父网卡；
  NAS 的其他网口/虚拟交换机（fnOS 的虚拟网桥）与它无关，不要选错。
- **macvlan 现象**：常驻模式下，NAS 自己 ping 不通中继容器的 IP（192.168.1.215），
  这是 macvlan 的正常限制，不影响中继工作；查看状态请用 `docker compose logs`。
- **IP 冲突**：常驻服务运行期间，不能再跑 `configure-env/baseline/try`
  （会报 address already in use）。先 `docker compose down` 再操作。
- **升级**：重新上传文件夹覆盖后，`bash scripts/build.sh` 重新构建，
  然后 `docker compose down && docker compose up -d`。
  注意：上游代码更新会使基线回执失效，需要重跑 `configure-env` + `baseline`。
