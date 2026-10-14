#!/usr/bin/env bash
# 本地多架构构建（linux/amd64 + linux/arm64）并推送。
# 用途：等不及 CI、或要推到自建 registry / Docker Hub。
# CI 走 .github/workflows/release.yml，正常发版不需要本脚本。
#
# 前置：本地已装 docker buildx + QEMU（一次即可）：
#   docker run --privileged --rm tonistiigi/binfmt --install all
#
# 用法：
#   # 推到 ghcr.io（需先 docker login ghcr.io -u <user> -p <PAT>）
#   REGISTRY=ghcr.io/<your-gh-user> TAG=v0.1.0 bash scripts/buildx-multiarch.sh
#
#   # 推到自建 registry（局域网，无需鉴权）
#   REGISTRY=192.168.1.10:5000 TAG=latest bash scripts/buildx-multiarch.sh
#
#   # 国内构建时给 pip 走清华源：
#   REGISTRY=... PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple bash scripts/buildx-multiarch.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${REGISTRY:?请设置 REGISTRY（如 ghcr.io/<user> 或 192.168.1.10:5000）}"
TAG=${TAG:-latest}
IMAGE="$REGISTRY/ps5-portal-relay:$TAG"
PIP_INDEX_URL=${PIP_INDEX_URL:-https://pypi.org/simple}

echo "==> 确保 buildx builder + QEMU"
docker buildx create --use --name portal-relay-builder 2>/dev/null || docker buildx use portal-relay-builder

echo "==> 多架构构建并推送：$IMAGE (amd64 + arm64)"
echo "    pip 走 $PIP_INDEX_URL"
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t "$IMAGE" \
  --build-arg "PIP_INDEX_URL=$PIP_INDEX_URL" \
  --push \
  .

echo "==> 完成。在目标机器上执行："
echo "    docker pull $IMAGE"