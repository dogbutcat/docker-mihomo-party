# Docker Mihomo Party

based on [linuxserver/baseimage-kasmvnc:debianbookworm](https://github.com/linuxserver/docker-baseimage-kasmvnc) add xfce gui and mihomo-party, and startup mihomo-party with boot.

remember to enable net.ipv4.ip_forward=1 in /etc/sysctl.conf

## CONFIG PATH

I'm using this as router, so I've decided make default running root user for TUN mode and add zerotier controled by environment variable `ZT`==true, also config path is `/mihomo-data/` with cmd `/usr/bin/mparty`.

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
      - "mihomo-data:/mihomo-data"
      - "zerotier:/var/lib/zerotier-one"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    security_opt:
      - seccomp=unconfined
    shm_size: "1gb"

volumes:
  - home
  - mihomo-data
  - zerotier
```
