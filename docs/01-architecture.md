# 1 · Architecture and network design

![Architecture](../assets/architecture.png)

## Machines

| | PC1 · Security gateway | PC2 · Automation hub | Test client |
|---|---|---|---|
| Hostname | `almi1server` | `almi2server` | Ubuntu Desktop |
| OS | Ubuntu Server 24.04.3 LTS | Ubuntu Server 24.04.3 LTS | Ubuntu Desktop |
| Lab IP (`enp0s3`) | `192.168.2.10/24` | `192.168.2.20/24` | lab network |
| Internet (`enp0s8`) | VirtualBox NAT (DHCP) | VirtualBox NAT (DHCP) | — |
| VPN | WireGuard server `10.0.0.1/24` | — | WireGuard client `10.0.0.2` |
| Software | Pi-hole v6, Fail2Ban, WireGuard | Docker 29.1.5, Compose v5.0.2 | WireGuard, SSH client |

## Network design

### Why two adapters

The first version of the lab ran on the classroom network (`192.168.2.0/24`) with static IPs and the classroom router (`192.168.2.1`) as the gateway. At home that gateway did not exist, so every service stopped working.

The first workaround was an extra **Ubuntu router VM** with two NICs: one on the home network, one on a `192.168.2.0/24` network, NATing between them. It worked but added a third machine to maintain.

The final design separates the two concerns with two VirtualBox adapters:

| Adapter | VirtualBox mode | Interface | Purpose |
|---|---|---|---|
| 1 | Host-only, `192.168.2.0/24` (host = `.1`) | `enp0s3` | Stable internal network: VM ↔ VM and Windows host ↔ VMs |
| 2 | NAT | `enp0s8` | Outbound Internet (Telegram, AWS, package updates) |

The internal interface has a static IP and **no default gateway**; the NAT interface gets IP, gateway and DNS from VirtualBox via DHCP. Result: the internal IPs never change, and the lab works on any physical network. The Windows host can open every web UI directly at `192.168.2.x` without port forwarding.

Netplan (PC1, PC2 is identical with `.20`): [`configs/pc1-gateway/netplan/50-cloud-init.yaml`](../configs/pc1-gateway/netplan/50-cloud-init.yaml)

```yaml
network:
  version: 2
  ethernets:
    enp0s3:              # host-only lab network
      dhcp4: no
      addresses: [192.168.2.10/24]
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
    enp0s8:              # VirtualBox NAT → Internet
      dhcp4: true
```

cloud-init network management is disabled (`/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`) so it does not overwrite this file on reboot.

### Docker network

On PC2 all containers share the bridge network `securenet` (`172.18.0.0/16`, created by Compose as `securenet_securenet`). Containers reach each other by name (`docker-socket-proxy`, `uptime-kuma`…); only the web UIs are published on the host.

## Ports

| Host | Port | Service | Exposed to |
|---|---|---|---|
| PC1 | 22/tcp | SSH (protected by Fail2Ban) | lab network |
| PC1 | 53/tcp+udp | Pi-hole DNS | lab network + VPN |
| PC1 | 80, 443/tcp | Pi-hole web UI + REST API | lab network |
| PC1 | 51820/udp | WireGuard | lab network |
| PC2 | 22/tcp | SSH (used by n8n for backups) | lab network |
| PC2 | 3000/tcp | Homepage | lab network |
| PC2 | 3001/tcp | Uptime Kuma | lab network |
| PC2 | 5678/tcp | n8n editor + webhooks | lab network |
| PC2 | 8080/tcp | Nextcloud | lab network |
| PC2 | 9000, 9443/tcp | Portainer | lab network |
| PC2 | 2375/tcp | docker-socket-proxy | **Docker network only** |

## Integration map

Who talks to whom, and how:

| From | To | Method / endpoint | When |
|---|---|---|---|
| Fail2Ban (PC1) | n8n | `POST http://192.168.2.20:5678/webhook/fail2ban` `{event, jail, ip, hostname, ts}` | on every ban |
| Uptime Kuma | monitored services | HTTP GET, expects 2xx | every 20 s |
| Uptime Kuma | n8n | `POST http://192.168.2.20:5678/webhook/kuma-alert` `{msg, monitor_code}` | on state change |
| n8n | docker-socket-proxy | `POST /containers/{name}/restart?t=5` | when a mapped service is DOWN |
| n8n | docker-socket-proxy | `GET /containers/json?all=1` | daily report |
| n8n | Pi-hole (PC1) | `POST /api/auth` → `GET /api/stats/summary` (headers `X-FTL-SID`, `X-FTL-CSRF`) | hourly |
| cron (PC2) | nmap | `scan.sh` → `/opt/n8n-files/scan.txt` | every 30 min |
| n8n | `scan.txt` | read from `/home/node/.n8n-files` (bind mount) | every 30 min + daily |
| n8n | PC2 host | SSH as `securenet-backup` → `/opt/securenet/backup.sh` | daily |
| `backup.sh` | AWS S3 | `aws s3 cp … s3://<bucket>/daily/` | daily |
| n8n | Telegram Bot API | `sendMessage` | end of every workflow |
| VPN client | PC1 | WireGuard UDP 51820 | on demand |

## Monitored services (Uptime Kuma)

| Monitor | URL | Interval |
|---|---|---|
| Homepage | `http://192.168.2.20:3000/` | 20 s |
| n8n | `http://192.168.2.20:5678/` | 20 s |
| Nextcloud | `http://192.168.2.20:8080/` | 20 s |
| Portainer | `https://192.168.2.20:9443/` | 20 s |
| Pi-hole | `http://192.168.2.10/admin/` | 20 s |
