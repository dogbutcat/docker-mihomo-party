# Docker Mihomo Party

基于 [dogbutcat/kasmvnc:ubuntunoble](https://github.com/dogbutcat/docker-kasmvnc) 基础镜像，添加 Mihomo Party 并设置开机自启。

> 使用 TUN 模式需要在宿主机启用 `net.ipv4.ip_forward=1`（写入 `/etc/sysctl.conf`）

## 配置说明

- 以 root 用户运行（支持 TUN 模式）
- 数据目录：`/mihomo-data/`
- 启动脚本：`/usr/bin/mparty`
- 可选 ZeroTier：环境变量 `ZT=true` 开启

## Build

```bash
docker buildx build --platform linux/amd64 --build-arg VERSION=$(cat VERSION) -t local/mihomo-party .
```

## Run

```yaml
version: "3.9"

services:
  mihomo-party:
    image: local/mihomo-party
    # image: dogbutcat/mihomo-party
    container_name: mihomo-party
    restart: unless-stopped
    environment:
      - PUID=0
      - PGID=0
      - USER=root
      # - ZT=true
    ports:
      - "3000:3000"
    network_mode: host
    volumes:
      - home:/config
      - mihomo-data:/mihomo-data
      - zerotier:/var/lib/zerotier-one
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    security_opt:
      - seccomp=unconfined
    shm_size: "1gb"

volumes:
  home:
  mihomo-data:
  zerotier:
```
