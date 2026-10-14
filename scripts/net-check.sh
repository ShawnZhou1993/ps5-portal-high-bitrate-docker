#!/usr/bin/env bash
# 部署前主机检查：Docker、父网卡、转发设置、br_netfilter 状态。
# 在飞牛NAS 或 R68S 上通过 SSH 运行：bash scripts/net-check.sh
set -u

ok()   { printf '  [OK] %s\n' "$*"; }
warn() { printf '  [!!] %s\n' "$*"; }
info() { printf '  [--] %s\n' "$*"; }

echo "==> Docker"
if command -v docker >/dev/null 2>&1; then
  ok "docker 已安装：$(docker --version)"
  if docker info >/dev/null 2>&1; then ok "docker 守护进程运行中"
  else warn "docker 守护进程未运行（飞牛：启动Docker应用；OpenWrt：/etc/init.d/docker start）"; fi
else
  warn "未找到 docker 命令"
fi

echo "==> 主机网卡（选择 PS5/Portal 所在局域网的有线网卡作为 LAN_PARENT）"
ip -br addr 2>/dev/null || ifconfig -a 2>/dev/null | grep -E '^[a-z]' || warn "找不到 ip/ifconfig 命令"

echo "==> 主机 IPv4 转发（主机允许为 1；容器内会被强制设为 0）"
fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "?")
info "net.ipv4.ip_forward = $fwd"

echo "==> br_netfilter（桥接流量是否过 iptables 的真正开关）"
if [ -d /sys/module/br_netfilter ]; then
  warn "br_netfilter 模块已加载（不等于会拦截，看下面的开关值）"
  for f in /proc/sys/net/bridge/bridge-nf-call-iptables /proc/sys/net/bridge/bridge-nf-call-ip6tables; do
    [ -f "$f" ] && info "$f = $(cat "$f" 2>/dev/null)"
  done
  info "开关为 0：桥接流量不过 iptables，无需处理"
  info "开关为 1：执行 sysctl -w net.bridge.bridge-nf-call-iptables=0，或加精准放行规则（见排障文档）"
else
  ok "br_netfilter 未加载（默认状态，macvlan 二层流量不受 iptables 影响）"
fi

echo "==> macvlan 支持（内核模块）"
if modinfo macvlan >/dev/null 2>&1 || grep -qw macvlan /proc/modules 2>/dev/null; then
  ok "macvlan 可用"
else
  warn "未检测到 macvlan 模块（较新内核通常内建；如 docker network create 报错请检查）"
fi

echo "==> 磁盘空间（镜像约 200-300MB，运行状态很小）"
df -h / 2>/dev/null | tail -1
