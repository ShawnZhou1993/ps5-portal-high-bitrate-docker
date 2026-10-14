# syntax=docker/dockerfile:1
# PS5 Portal 高码率中继容器（多架构：linux/amd64 + linux/arm64）
# 构建上下文 = 本目录；src/ 内为上游源码，未做任何修改（保持基线指纹一致）
FROM alpine:3.22

LABEL org.opencontainers.image.title="ps5-portal-relay" \
      org.opencontainers.image.description="Experimental PS Portal -> PS5 Remote Play bitrate relay (auto mode), multi-arch Docker build" \
      org.opencontainers.image.source="https://github.com/atameric/ps5-portal-high-bitrate" \
      org.opencontainers.image.licenses="MIT"

ARG SOURCE_REV=unknown
# 可选：构建时指定 pip 源（国内网络加速用），例如：
#   docker build --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple .
ARG PIP_INDEX_URL=https://pypi.org/simple
ENV PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_DISABLE_PIP_VERSION_CHECK=1
COPY src/ /src/
# 防御 CRLF：若构建上下文来自 Windows 签出（git autocrlf 会把上游 LF 文件转成 CRLF），
# ash 执行 "set -eu\r" 会直接报 illegal option。上游仓库原始行尾即 LF，此处统一去掉 CR。
RUN find /src -type f -exec sh -c 'tr -d "\015" < "$1" > "$1.tmp" && mv "$1.tmp" "$1"' _ {} \;
# 安装即自检：BPF 过滤器编译 + 上游单元测试（构建失败会在此中断）
RUN PORTAL_CONTAINER=1 PORTAL_SOURCE_REV="$SOURCE_REV" sh /src/deploy/install-alpine.sh \
 && rm -rf /src /root/.cache

# 新增：非交互注册入口（configure-env），不改动上游代码
COPY docker/docker_configure.py /opt/portal-bitrate-auto/docker_configure.py
COPY docker/portal-docker /usr/local/bin/portal-docker
RUN chmod 0755 /usr/local/bin/portal-docker /opt/portal-bitrate-auto/docker_configure.py

ENV PORTAL_CONTAINER=1
VOLUME ["/etc/portal-bitrate", "/var/lib/portal-bitrate-auto"]

# status.json 在中继运行期间每 2 秒重写一次
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["/usr/local/bin/portal", "health"]

ENTRYPOINT ["/usr/local/bin/portal-docker"]
CMD ["service"]
