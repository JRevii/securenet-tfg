# 2 · PC1 · Security gateway

PC1 (`almi1server`, `192.168.2.10`) runs the network-security services directly on Ubuntu Server 24.04, without Docker.

| Service | Version | Config in this repo |
|---|---|---|
| Pi-hole | Core 6.3 · Web 6.4 · FTL 6.4.1 | [`configs/pc1-gateway/pihole/`](../configs/pc1-gateway/pihole) |
| Fail2Ban | Ubuntu 24.04 package | [`configs/pc1-gateway/fail2ban/`](../configs/pc1-gateway/fail2ban) |
| WireGuard | Ubuntu 24.04 package | [`configs/pc1-gateway/wireguard/`](../configs/pc1-gateway/wireguard) |

## Pi-hole v6 · DNS filtering

- Listens on `enp0s3` (lab network), `listeningMode = LOCAL`.
- Upstream DNS: `8.8.8.8`, `8.8.4.4`.
- Blocklists: StevenBlack hosts, AdguardDNS, KADhosts → **~68,000 blocked domains**.
- Web UI: `http://192.168.2.10/admin`.

### REST API (v6)

Pi-hole v6 replaced the old `admin/api.php?summaryRaw` endpoint with a REST API that uses **session authentication**. Bearer tokens and Basic Auth return `401`; the working flow is:

```bash
# 1. Log in with the web password → returns session.sid and session.csrf
curl -s -X POST http://192.168.2.10/api/auth \
  -H "Content-Type: application/json" -d '{"password":"<PIHOLE_WEB_PASSWORD>"}'

# 2. Use the session on any endpoint
curl -s http://192.168.2.10/api/stats/summary \
  -H "X-FTL-SID: <sid>" -H "X-FTL-CSRF: <csrf>"
```

This is exactly what [workflow 1](04-workflows.md#1--pi-hole-stats) does.

## Fail2Ban · SSH brute-force protection

[`jail.local`](../configs/pc1-gateway/fail2ban/jail.local):

```ini
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
mode    = normal
action  = %(action_)s
          n8n-webhook
```

- `backend = systemd` reads SSH failures from the journal; the ban itself uses **nftables** (Ubuntu default `banaction`).
- `action = %(action_)s` keeps the normal ban. The first version used only `action = n8n`, which sent the alert **but stopped banning**; adding `%(action_)s` back fixed it.

Custom action [`n8n-webhook.conf`](../configs/pc1-gateway/fail2ban/action.d/n8n-webhook.conf) — on every ban it notifies n8n:

```ini
[Definition]
actionban = curl -sS -m 5 -X POST "http://192.168.2.20:5678/webhook/fail2ban" \
  -H "Content-Type: application/json" \
  -d "{\"event\":\"BAN\",\"jail\":\"<name>\",\"ip\":\"<ip>\",\"hostname\":\"$(hostname)\",\"ts\":\"$(date -Iseconds)\"}"
```

Useful commands:

```bash
sudo fail2ban-client status sshd
sudo fail2ban-client set sshd banip 192.168.2.123     # manual test
sudo fail2ban-client set sshd unbanip 192.168.2.123
sudo tail -f /var/log/fail2ban.log
```

## WireGuard · VPN

Server [`wg0.conf.example`](../configs/pc1-gateway/wireguard/wg0.conf.example): tunnel `10.0.0.1/24`, port `51820/udp`, one peer (`10.0.0.2/32`). `PostUp` adds a FORWARD rule and NAT (`MASQUERADE` out of `enp0s3`) so VPN clients can reach the lab network; `net.ipv4.ip_forward=1` is set in `/etc/sysctl.conf`.

```bash
wg genkey | tee privatekey | wg pubkey > publickey   # key pair
sudo wg-quick up wg0 && sudo systemctl enable wg-quick@wg0
sudo wg show                                          # handshake / peers
```

Client [`client.conf.example`](../configs/pc1-gateway/wireguard/client.conf.example): `10.0.0.2/24`, DNS = Pi-hole, endpoint `192.168.2.10:51820`, `PersistentKeepalive = 25`.

**Known v1 limitations** (see [security review](08-security-review.md)):

- The test client was on the same network as the server, so the tunnel did not demonstrate real remote access.
- `AllowedIPs = 10.0.0.0/24` routes only the tunnel subnet; traffic to `192.168.2.0/24` (services and Pi-hole) went outside the tunnel.
- The client key pair was generated on the server.

## Rebuild PC1 (summary)

```bash
sudo apt update && sudo apt install -y fail2ban wireguard curl nmap
curl -sSL https://install.pi-hole.net | bash               # choose enp0s3
sudo cp configs/pc1-gateway/fail2ban/jail.local /etc/fail2ban/
sudo cp configs/pc1-gateway/fail2ban/action.d/n8n-webhook.conf /etc/fail2ban/action.d/
sudo systemctl restart fail2ban
# WireGuard: create keys, fill wg0.conf.example → /etc/wireguard/wg0.conf, then wg-quick up wg0
```
