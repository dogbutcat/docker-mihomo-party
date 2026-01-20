FROM ghcr.io/linuxserver/baseimage-kasmvnc:ubuntunoble

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 1. Minimal XFCE4 Installation + Timezone
# Use --no-install-recommends to avoid bloat/conflicting power managers
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    x11-xserver-utils \
    adwaita-icon-theme-full \
    wget \
    vim \
    tzdata \
    fonts-wqy-microhei \
    fonts-wqy-zenhei && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get install -y --no-install-recommends ca-certificates && \
    install -d -m 0755 /etc/apt/keyrings && \
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null && \
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | tee -a /etc/apt/sources.list.d/mozilla.list > /dev/null && \
    echo 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000' | tee /etc/apt/preferences.d/mozilla && \
    apt-get update && \
    apt-get install -y --no-install-recommends firefox

# 2. Explicitly remove conflicting power management tools if installed
RUN apt-get purge -y upower xfce4-power-manager || true

# 3. KasmVNC & GPU Hang Fixes (Mac Docker Compatibility)
ENV LIBGL_ALWAYS_SOFTWARE=1

RUN curl -s https://install.zerotier.com | bash

RUN cp -r /var/lib/zerotier-one/ /var/lib/zerotier-one.bak/

ENV LC_ALL=en_US.UTF-8
# 配置中文语言环境
# RUN sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen && \
#     locale-gen zh_CN.UTF-8

# Additional deps for clash-verge
# RUN apt-get install -y libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18 libayatana-appindicator3-1

ARG VERSION
ARG TARGETARCH

# get Clash Party from git repo
RUN wget -q -O - https://github.com/mihomo-party-org/clash-party/releases/download/v${VERSION}/clash-party-linux-${VERSION}-${TARGETARCH}.deb -O /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb

COPY root /
COPY .Xauthority /config/.Xauthority

RUN chmod 644 /etc/xdg/autostart/mihomo-party.desktop

# Install Mihomo Party.
RUN apt-get install -y /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb \
    && rm /tmp/clash-party-linux-${VERSION}-${TARGETARCH}.deb

# 创建 Mihomo Party 数据目录并设置为 VOLUME
RUN mkdir -p /mihomo-data
VOLUME "/mihomo-data"
VOLUME "/var/lib/zerotier-one"

# 暴露端口（继承自基础镜像）
EXPOSE 3000

ENV HOME=/config
ENV ZT=false