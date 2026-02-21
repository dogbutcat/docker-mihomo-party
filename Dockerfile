# ========== Stage 1: Go builder for warp-endpoint-probe ==========
FROM golang:1.24-alpine AS warp-probe-builder
ARG TARGETARCH
COPY warp-endpoint-probe/ /src/
WORKDIR /src
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o /warp-endpoint-probe .

# ========== Stage 2: Main image ==========
FROM dogbutcat/kasmvnc:ubuntunoble

# ZeroTier
RUN curl -s https://install.zerotier.com | bash
RUN cp -r /var/lib/zerotier-one/ /var/lib/zerotier-one.bak/

ARG VERSION
ARG TARGETARCH

# Add cloudflare gpg key
# curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
# # Add this repo to your apt repositories
# echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
# # Install
# sudo apt-get update && sudo apt-get install cloudflare-warp

# ---------- Cloudflare WARP ----------
# 基础镜像可能缺少 gnupg，先确保安装；硬编码 noble，若不可用自动回退 jammy
RUN    apt-get update; \
    apt-get install -y --no-install-recommends gnupg
RUN    curl -4 -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
RUN    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ noble main" \
      > /etc/apt/sources.list.d/cloudflare-warp.list
RUN    apt-get update; \
    apt-get install -y --no-install-recommends cloudflare-warp dbus iptables iproute2; \
    apt-get clean; rm -rf /var/lib/apt/lists/*
# iptables-nft 与 DinD / WARP 网关不兼容，切回 legacy
RUN    update-alternatives --set iptables /usr/sbin/iptables-legacy

# ---------- gost v3 (SOCKS5 / Shadowsocks 代理) ----------
ARG GOST_VERSION=3.2.6
RUN set -eux; \
    wget -qO /tmp/gost.tar.gz \
      "https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    tar -xzf /tmp/gost.tar.gz -C /tmp gost; \
    install -m 755 /tmp/gost /usr/local/bin/gost; \
    rm -f /tmp/gost /tmp/gost.tar.gz

# 下载 Clash Party deb 包
RUN wget -q -O /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb \
    https://github.com/mihomo-party-org/clash-party/releases/download/v${VERSION}/clash-party-linux-${VERSION}-${TARGETARCH}.deb

# ---------- warp-endpoint-probe (from Go builder) ----------
COPY --from=warp-probe-builder /warp-endpoint-probe /usr/local/bin/warp-endpoint-probe
COPY warp-speed-test.sh /usr/local/bin/warp-speed-test.sh
RUN chmod +x /usr/local/bin/warp-endpoint-probe /usr/local/bin/warp-speed-test.sh

COPY root /
COPY .Xauthority /config/.Xauthority

RUN chmod 644 /etc/xdg/autostart/mihomo-party.desktop

# ---------- WARP 脚本权限 ----------
RUN chmod +x /usr/bin/generate-mdm-xml /usr/bin/restart-gost && \
    find /etc/s6-overlay/s6-rc.d -name "run" -exec chmod +x {} \;

# ---------- 禁用基础镜像自带的 DinD ----------
RUN touch /etc/s6-overlay/s6-rc.d/svc-docker/down

# 安装 Clash Party 并清理
RUN apt-get update && \
    apt-get install -y /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*.deb

RUN mkdir -p /mihomo-data
VOLUME "/mihomo-data"
# VOLUME "/var/lib/zerotier-one"
# VOLUME "/var/lib/cloudflare-warp"

EXPOSE 3000
EXPOSE 1080
EXPOSE 8388

ENV ZT=false

# === WARP 主开关 ===
ENV WARP=false

# === WARP 配置 (仅 WARP=true 时生效) ===
ENV WARP_MODE=
ENV WARP_LICENSE_KEY=
ENV WARP_PROXY_PORT=40000

# === 代理配置 ===
ENV PROXY_TYPE=
ENV PROXY_PORT=1080
ENV SS_PASSWORD=
ENV SS_METHOD=chacha20-ietf-poly1305
ENV SS_PORT=8388

# === MDM 部署 ===
ENV WARP_MDM_ENABLED=false
ENV WARP_ORG=
ENV WARP_AUTH_CLIENT_ID=
ENV WARP_AUTH_CLIENT_SECRET=
ENV WARP_SERVICE_MODE=
ENV WARP_TUNNEL_PROTOCOL=masque
ENV WARP_SWITCH_LOCKED=
ENV WARP_AUTO_CONNECT=
ENV WARP_ONBOARDING=
ENV WARP_DISPLAY_NAME=
ENV WARP_SUPPORT_URL=
ENV WARP_GATEWAY_ID=
ENV WARP_ENABLE_PMTUD=
ENV WARP_ENABLE_POST_QUANTUM=
ENV WARP_ENABLE_NETBT=
ENV WARP_OVERRIDE_API_ENDPOINT=
ENV WARP_OVERRIDE_DOH_ENDPOINT=
ENV WARP_OVERRIDE_WARP_ENDPOINT=
ENV WARP_EMERGENCY_SIGNAL_URL=
ENV WARP_EMERGENCY_SIGNAL_FINGERPRINT=
ENV WARP_EMERGENCY_SIGNAL_INTERVAL=

# === IP 优选 ===
ENV WARP_IP_SELECTION_ENABLED=false
ENV WARP_API_SELECTION_ENABLED=false
ENV WARP_IPV6_SELECTION=false
ENV WARP_LOG_LEVEL=info
ENV WARP_PROBE_TIMEOUT=30s
ENV WARP_PROBE_CONCURRENCY=400
ENV WARP_PROBE_ROUNDS=3
ENV WARP_PROBE_SAMPLE=0

# === 网关模式 ===
ENV GATEWAY_MODE=false
ENV GATEWAY_ROUTES=

# === 路由修复 (Clash Tun + WARP/ZeroTier 共存) ===
ENV ROUTING_MARK=6666