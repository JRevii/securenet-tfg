<div align="center">

# SecureNet

**Automated security, monitoring and incident-response lab**

Final degree project (TFG) · Microcomputer Systems and Networks (SMR) · ALMI, Bilbao · 2026

![Ubuntu](https://img.shields.io/badge/Ubuntu_Server-24.04-E95420?logo=ubuntu&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![n8n](https://img.shields.io/badge/n8n-automation-EA4B71?logo=n8n&logoColor=white)
![WireGuard](https://img.shields.io/badge/WireGuard-VPN-88171A?logo=wireguard&logoColor=white)
![Pi-hole](https://img.shields.io/badge/Pi--hole-v6-96060C?logo=pihole&logoColor=white)
![AWS S3](https://img.shields.io/badge/AWS-S3-FF9900?logo=amazons3&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-alerts-26A5E4?logo=telegram&logoColor=white)
![Status](https://img.shields.io/badge/status-v1_archived-lightgrey)

[Español](README.es.md) · **English**

</div>

---

SecureNet is a two-VM lab that **detects incidents and reacts to them on its own**: it bans SSH brute-force attackers, restarts crashed services, scans the network, filters DNS, ships encrypted backups to AWS and reports everything to Telegram in real time.

This repository is the **archived v1**, exactly as it was delivered and graded in February 2026: real configuration files (secrets removed), the six n8n workflows exported from the running system, screenshots, logs-based evidence and an honest post-delivery security review.

![SecureNet v1 architecture](assets/architecture.png)

## What it does

| # | Automation | Trigger | What happens |
|---|---|---|---|
| 1 | **Intrusion response** | SSH brute force on the gateway | Fail2Ban bans the IP (nftables) and calls an n8n webhook → Telegram alert |
| 2 | **Self-healing services** | Uptime Kuma detects a service DOWN | n8n de-duplicates the event, restarts the container through the Docker API and reports DOWN/UP |
| 3 | **DNS visibility** | Every hour | n8n logs into the Pi-hole v6 REST API (session SID + CSRF) and sends query/block stats |
| 4 | **Network discovery** | Every 30 min | `nmap` ARP scan of the lab subnet → n8n parses IP / MAC / vendor → Telegram |
| 5 | **Encrypted off-site backups** | Daily | n8n runs `backup.sh` over SSH: MariaDB dump + Docker volumes → AES-256 (PBKDF2) → AWS S3 |
| 6 | **Daily report** | Daily | Docker status (via API), scan results and counters merged into one Telegram summary |

Plus a **WireGuard VPN** into the lab network and a **Homepage** dashboard that links every service.

## See it working

| Self-healing workflow (n8n) | Real alerts on Telegram |
|---|---|
| ![Auto-recovery workflow](assets/screenshots/n8n-autorrecuperacion.png) | ![Telegram recovery alert](assets/screenshots/telegram-homepage-recovered.png) |

| Uptime Kuma | Pi-hole v6 |
|---|---|
| ![Uptime Kuma](assets/screenshots/uptime-kuma-dashboard.png) | ![Pi-hole](assets/screenshots/pihole-dashboard.png) |

| Homepage dashboard | Containers (Portainer) |
|---|---|
| ![Homepage](assets/screenshots/homepage-dashboard.png) | ![Portainer](assets/screenshots/portainer-containers.png) |

More screenshots in [`assets/screenshots`](assets/screenshots) and per-workflow in [docs/04-workflows.md](docs/04-workflows.md).

## Architecture in short

| Machine | Role | Runs |
|---|---|---|
| **PC1** `192.168.2.10` | Security gateway | Pi-hole v6 · Fail2Ban · WireGuard (bare metal on Ubuntu) |
| **PC2** `192.168.2.20` | Automation hub | Docker: n8n · Uptime Kuma · docker-socket-proxy · Homepage · Portainer · Nextcloud + MariaDB |
| **Client** `10.0.0.2` | VPN client / attacker | Ubuntu Desktop used for VPN tests and the brute-force demo |

Both VMs sit on a VirtualBox **host-only network** (`192.168.2.0/24`) for internal traffic and use a **NAT adapter** for Internet access, so the lab works the same in the classroom or at home. Details: [docs/01-architecture.md](docs/01-architecture.md).

## Evidence from the real system

- **9 real bans** recorded by Fail2Ban between 23 and 27 Feb 2026, including an automated attack of **57 failed SSH logins in three waves within one minute**, each wave banned within a second.
- **~9,600 health checks** stored by Uptime Kuma since 10 Feb 2026: **81 outages detected and 84 recoveries** logged across the five monitored services.
- Telegram alerts for intrusions, outages, recoveries, scans and daily reports (see [docs/06-testing-and-evidence.md](docs/06-testing-and-evidence.md)).

## Post-delivery security review

After the project was graded I audited the running system again, file by file, as if it were someone else's. That review found **13 functional bugs and 8 security weaknesses**: for example, the network scanner never actually compared against known devices, the daily counters could never be incremented, the backup always reported success, and the n8n webhooks accepted unauthenticated requests that could restart containers.

Every finding, its root cause and the planned fix are documented in [docs/08-security-review.md](docs/08-security-review.md). They are the starting point for SecureNet v2.

## Repository structure

```
.
├── assets/                 architecture diagram + screenshots
├── configs/
│   ├── pc1-gateway/        netplan, Fail2Ban, WireGuard, Pi-hole, sysctl
│   └── pc2-automation-hub/ docker-compose, .env.example, Homepage, netplan, crontab
├── docs/                   architecture, setup, workflows, backups, tests, troubleshooting, security review
├── scripts/                scan.sh (nmap) · backup.sh (dump + encrypt + S3)
└── workflows/              the 6 n8n workflows (+1 legacy) exported from the live system
```

## Documentation

1. [Architecture and network design](docs/01-architecture.md)
2. [PC1 · Security gateway](docs/02-pc1-security-gateway.md)
3. [PC2 · Automation hub](docs/03-pc2-automation-hub.md)
4. [n8n workflows](docs/04-workflows.md)
5. [Encrypted backups](docs/05-backups.md)
6. [Testing and evidence](docs/06-testing-and-evidence.md)
7. [Troubleshooting log and lessons learned](docs/07-troubleshooting-log.md)
8. [Post-delivery security review](docs/08-security-review.md)

## What I learned

- Designing a **portable network** (host-only + NAT) instead of depending on the classroom router.
- Integrating tools through **webhooks and REST APIs** (Pi-hole v6 session auth, Docker API, Telegram).
- Giving automation **least privilege**: n8n restarts containers through a socket proxy instead of mounting the Docker socket.
- **Persistence and secrets** in Docker: volumes, file permissions, a fixed n8n encryption key.
- Debugging real failures: 50+ issues documented in the [troubleshooting log](docs/07-troubleshooting-log.md).
- And the most important one: **a feature is not done until you can prove it works**. The post-delivery review taught me more than the build itself.

## Tech stack

Ubuntu Server 24.04 · VirtualBox · Docker 29 / Compose v5 · n8n 2.4 · Uptime Kuma 1 · Pi-hole v6 · Fail2Ban · WireGuard · nmap · Portainer CE · Homepage · Nextcloud 29 · MariaDB 11 · AWS CLI v2 / S3 · OpenSSL · Telegram Bot API

## Notes

- **Secrets:** all passwords, keys, tokens and IDs were removed or replaced with placeholders (`<...>`, `${...}`). The real ones were never committed.
- **VM images** (`.ova`, ~10 GB) are not included; the configuration in this repo is enough to rebuild the lab.
- **Status:** v1 is frozen. Improvements happen in SecureNet v2.

## Author

**Jon Revillas** · [GitHub @JRevii](https://github.com/JRevii)

Licensed under the [MIT License](LICENSE).
