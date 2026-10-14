#!/usr/bin/env python3
"""Docker 非交互注册：从环境变量读取 PS5_IP / PORTAL_IP / PROFILE / IFACE，
复用上游 portal_auto 的注册逻辑（配置校验 + ARP 解析双方 MAC）并写入
auto-config.json。本文件不修改任何上游协议代码，只是入口包装。

对应上游交互式命令：portal configure [65|100|200]
"""
import ipaddress
import json
import os
import sys
from pathlib import Path

APP = Path(os.environ.get('PORTAL_APP', '/opt/portal-bitrate-auto'))
sys.path.insert(0, str(APP))

import portal_auto as auto          # noqa: E402
import portal_auto_platform as net  # noqa: E402

CFG = Path(os.environ.get('PORTAL_CONFIG', '/etc/portal-bitrate/auto-config.json'))
LOCK = Path(os.environ.get('PORTAL_LOCK', '/run/portal-lab-capture.lock'))


def fail(message):
    print(f'ERROR: {message}', file=sys.stderr)
    return 1


def main():
    # geteuid 仅存在于 Linux；容器内必然是 Linux，这里做兼容以便本地自测
    if hasattr(os, 'geteuid') and os.geteuid() != 0:
        return fail('容器内需要以 root 运行（Docker 默认即为 root，无需额外设置）。')
    if LOCK.exists():
        return fail(f'检测到中继锁 {LOCK}，说明中继正在运行。'
                    '请先执行 docker compose down（或 docker rm -f portal-relay）停止服务后再注册。')
    ps5_ip = os.environ.get('PS5_IP', '').strip()
    portal_ip = os.environ.get('PORTAL_IP', '').strip()
    iface = os.environ.get('IFACE', 'eth0').strip() or 'eth0'
    profile = os.environ.get('PROFILE', '65').strip() or '65'
    if not ps5_ip or not portal_ip:
        return fail('请设置 PS5_IP 和 PORTAL_IP 环境变量（写入 .env，或用 -e PS5_IP=... 传入）。')
    if profile not in auto.PROFILES:
        return fail(f'PROFILE 只能是 {"/".join(auto.PROFILES)}，当前值为 {profile!r}。')
    try:
        ps5_addr = ipaddress.IPv4Address(ps5_ip)
        portal_addr = ipaddress.IPv4Address(portal_ip)
    except ValueError:
        return fail('PS5_IP / PORTAL_IP 必须是合法的 IPv4 地址。')
    if ps5_addr == portal_addr or any(
            a.is_multicast or a.is_loopback or a.is_unspecified or a.is_reserved
            for a in (ps5_addr, portal_addr)):
        return fail('PS5 与 Portal 需要是两个不同的单播 IPv4 地址。')

    c = {'network': {'interface': iface, 'ps5_ip': ps5_ip, 'portal_ip': portal_ip},
         'profile': profile}
    print(f'注册参数：PS5={ps5_ip}  Portal={portal_ip}  网卡={iface}  档位={profile}')
    print('请确认 PS5 和 Portal 均已开机唤醒，且与中继在同一局域网…')
    try:
        # 上游逻辑：健康检查（转发必须关闭、双机同网段直连）+ ARP 解析双方 MAC
        state = net.state_for(c, enroll=True)
    except Exception as exc:
        return fail(f'注册失败：{exc}')
    c.update(network=state['config'], ps5_mac=state['ps5_mac'], portal_mac=state['portal_mac'])
    CFG.parent.mkdir(parents=True, exist_ok=True)
    auto.atomic_json(CFG, c)
    print(f'注册完成：PS5 MAC={c["ps5_mac"]}，Portal MAC={c["portal_mac"]}')
    print('下一步：把 Portal 从 PS5 上断开，然后运行 baseline（60 秒透传测试）。')
    print('注意：auto-config.json 包含你局域网设备的 IP/MAC 信息，请勿外传。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
