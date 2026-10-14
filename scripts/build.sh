#!/usr/bin/env bash
# 在本机构建镜像：飞牛NAS(X86) 上构建出 amd64 镜像，R68S(ARM64) 上构建出 arm64 镜像。
# 构建过程会自动运行上游单元测试，失败则构建中断。
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=${IMAGE:-portal-relay:local}
SOURCE_REV=${SOURCE_REV:-unknown}

echo "==> 构建镜像 $IMAGE"
docker build --build-arg SOURCE_REV="$SOURCE_REV" -t "$IMAGE" .

echo "==> 镜像内复跑上游单元测试"
docker run --rm --workdir /opt/portal-bitrate-auto \
  --entrypoint /opt/portal-bitrate-auto/.venv/bin/python \
  "$IMAGE" -m unittest discover -s tests 2>&1 | tail -3

echo "==> 冒烟测试：入口与版本"
docker run --rm "$IMAGE" version
docker run --rm "$IMAGE" help | head -5

echo "==> 完成：$IMAGE"
