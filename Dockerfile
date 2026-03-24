FROM dogbutcat/kasmvnc:ubuntunoble

# ZeroTier
RUN curl -s https://install.zerotier.com | bash
RUN cp -r /var/lib/zerotier-one/ /var/lib/zerotier-one.bak/

ARG VERSION
ARG TARGETARCH

# 下载 Clash Party deb 包
RUN wget -q -O /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb \
    https://github.com/mihomo-party-org/clash-party/releases/download/v${VERSION}/clash-party-linux-${VERSION}-${TARGETARCH}.deb

COPY root /
COPY .Xauthority /config/.Xauthority

RUN chmod 644 /etc/xdg/autostart/mihomo-party.desktop

# ---------- 禁用基础镜像自带的 DinD ----------
RUN touch /etc/s6-overlay/s6-rc.d/svc-docker/down

# 安装 Clash Party 并清理
RUN apt-get update && \
    apt-get install -y /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*.deb

RUN mkdir -p /mihomo-data
VOLUME "/mihomo-data"

EXPOSE 3000

ENV ZT=false