# Docker Mihomo Party

基于 [dogbutcat/kasmvnc:ubuntunoble](https://github.com/dogbutcat/docker-kasmvnc) 基础镜像，添加 Mihomo Party 并设置开机自启。

> 使用 TUN 模式需要在宿主机启用 `net.ipv4.ip_forward=1`（写入 `/etc/sysctl.conf`）

## 配置说明

- 以 root 用户运行（支持 TUN 模式）
- 数据目录：`/mihomo-data/`
- 启动脚本：`/usr/bin/mparty`
- 可选 ZeroTier：环境变量 `ZT=true` 开启
- 可选 WARP 代理：环境变量 `WARP=true` 开启（详见下方 WARP 章节）

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
    # image: ghcr.io/dogbutcat/mihomo-party
    container_name: mihomo-party
    restart: unless-stopped
    environment:
      - PUID=0
      - PGID=0
      - USER=root
      # - ZT=true
      # === WARP 代理 (可选) ===
      # - WARP=true
      # - WARP_LICENSE_KEY=xxxxxxxx-xxxxxxxx-xxxxxxxx
      # - WARP_MODE=proxy
      # - PROXY_TYPE=socks5
      # - PROXY_PORT=1080
      # --- IP 优选 (可选) ---
      # - WARP_IP_SELECTION_ENABLED=true
      # - WARP_API_SELECTION_ENABLED=true
    ports:
      - "3000:3000"
      # - "1080:1080"    # gost SOCKS5 (WARP=true 时)
      # - "8388:8388"    # Shadowsocks (socks5+ss 模式时)
    network_mode: host
    volumes:
      - home:/config
      - mihomo-data:/mihomo-data
      - zerotier:/var/lib/zerotier-one
      - cloudflare-warp:/var/lib/cloudflare-warp
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
  cloudflare-warp:
```

## WARP 代理

通过 `WARP=true` 环境变量启用 Cloudflare WARP 代理功能（整合自 [docker-warp](https://github.com/dogbutcat/docker-warp)）。

> Mihomo Party 默认混合代理端口为 `7890`，与 gost 默认端口 `1080` 不冲突。若自行修改了 Mihomo Party 端口为 `1080`，可通过 `PROXY_PORT` 环境变量调整 gost 端口避免冲突。

### WARP 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WARP` | `false` | 主开关，设为 `true` 启用 WARP |
| `WARP_MODE` | (空) | WARP 模式：`warp` / `doh` / `warp+doh` / `dot` / `warp+dot` / `proxy` / `tunnel_only` |
| `WARP_LICENSE_KEY` | (空) | WARP+ 许可证密钥 |
| `WARP_PROXY_PORT` | `40000` | WARP proxy 模式内部监听端口 |
| `PROXY_TYPE` | (空) | gost 代理类型：`socks5` / `ss` / `socks5+ss` / `none`，不设则不启动 gost |
| `PROXY_PORT` | `1080` | gost 外部代理端口 |
| `SS_PASSWORD` | (空) | Shadowsocks 密码（ss / socks5+ss 模式必填） |
| `SS_METHOD` | `chacha20-ietf-poly1305` | Shadowsocks 加密方式 |
| `SS_PORT` | `8388` | Shadowsocks 端口（仅 socks5+ss 模式） |
| `WARP_MDM_ENABLED` | `false` | MDM 部署主开关 |
| `WARP_ORG` | (空) | Zero Trust 组织名 |
| `WARP_AUTH_CLIENT_ID` | (空) | Service Token Client ID |
| `WARP_AUTH_CLIENT_SECRET` | (空) | Service Token Client Secret |
| `WARP_SERVICE_MODE` | (空) | MDM 服务模式 |
| `WARP_TUNNEL_PROTOCOL` | `masque` | 隧道协议：`masque` / `wireguard` |
| `GATEWAY_MODE` | `false` | 网关模式主开关 |
| `GATEWAY_ROUTES` | (空) | 路由到 WARP 隧道的目标网段，逗号分隔 |

### Endpoint 覆盖

手动指定端点 IP，跳过优选直接使用。适用于中国网络伙伴等特殊场景。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WARP_OVERRIDE_WARP_ENDPOINT` | (空) | 覆盖 WARP 隧道端点 IP:Port |
| `WARP_OVERRIDE_API_ENDPOINT` | (空) | 覆盖 API 端点 IP |
| `WARP_OVERRIDE_DOH_ENDPOINT` | (空) | 覆盖 DoH 端点 IP |

### Endpoint 优选 (IP Selection)

自动探测最快端点并写入 MDM 配置。启用后在容器启动时自动运行。

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WARP_IP_SELECTION_ENABLED` | `false` | 是否开启隧道 Endpoint 优选 (测速挑选最快 IP) |
| `WARP_API_SELECTION_ENABLED` | `false` | 是否开启 API Endpoint 优选 (测速挑选最快节点，仅 MDM 有效) |
| `WARP_IPV6_SELECTION` | `false` | 优选时是否包含 IPv6 地址 |
| `WARP_PROBE_TIMEOUT` | `30s` | 优选总最大超时时间 |
| `WARP_PROBE_CONCURRENCY` | `400` | 并发探测数量 (降低可减少资源消耗) |
| `WARP_PROBE_ROUNDS` | `3` | 每个 Endpoint 探测轮数并取平均值，提升稳定性 |
| `WARP_PROBE_SAMPLE` | `0` | 每个 CIDR 采样 IP 数量 (设为 5 可快速预筛) |
| `WARP_LOG_LEVEL` | `info` | 优选日志级别：`debug` / `info` / `warn` / `error` |

完整变量及注释请参考 `.env.example`。
