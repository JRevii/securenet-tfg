# 8 · Post-delivery security review

In October 2026, eight months after the project was graded, I restored both VMs and audited SecureNet as if it were someone else's system. I went through the real configuration files, the exported n8n workflows, the Uptime Kuma database, the system logs and the shell history, and compared what the system **actually does** with what the project documentation **said it did**.

**Result: 13 functional bugs, 8 security weaknesses and 3 design limitations.** None of them showed up in the live demos, which is exactly why this review matters.

---

## Functional bugs

| # | Bug | Root cause (evidence) | Impact | Fix in v2 |
|---|---|---|---|---|
| B1 | A literal `=` appears before values in Telegram messages | The Set node writes `"={{ ... }}"` inside a JSON that is already an expression; the Pi-hole and report templates start with `=={{` | Cosmetic, but looks broken | One shared message-formatting function, no nested expression markers |
| B2 | The "new devices" scanner reports **every** host, every 30 min | Workflow 4 never compares against anything; `known_devices.json` is empty (`[]`) and unused | No real new-device detection; alert fatigue | Persist a baseline (MAC → first seen) and alert only on differences |
| B3 | Daily report always shows `0` bans and `0` outages | Counters are read from workflow 6's static data, but nothing ever writes them: static data is **per workflow**, not shared | Report misses the most important numbers | Store events in a shared place (database / n8n data table) and count from there |
| B4 | Backup always reports "OK" | The Code node looks for `EXIT_CODE:` that the script never prints, and the Telegram message ignores the result; an SSH failure stops the workflow silently | A failed backup is invisible | Explicit exit status, error branch and failure alert |
| B5 | Unmapped services are announced as **"SERVICIO RECUPERADO"** | A DOWN without a container mapping becomes `status: ERROR`, which goes down the IF's *false* branch, wired to the "recovered" template. Nextcloud and Pi-hole are not in the map | Misleading alert during a real outage; Nextcloud is never auto-restarted | Explicit branches for DOWN / UP / ERROR, full mapping, PC1 services handled separately |
| B6 | n8n monitor sends the wrong service code | The Kuma notification for n8n sends `monitor_code: HOMEPAGE` and a literal `"..."` message; n8n is also in the restart map | An n8n outage would restart Homepage; n8n could try to restart itself | Correct notification; never self-restart n8n; external watchdog |
| B7 | Fragile de-duplication | `If drop` compares `"={{$json.drop}} "` (trailing space) to a boolean with loose type validation | Duplicates sometimes not dropped, or valid events dropped | Strict boolean comparison |
| B8 | Malformed HTTP details | Header name `" X-FTL-CSRF"` and SID value with a leading space; restart URL ends in `\n` | Works by luck; breaks on stricter versions | Clean values, tested with the API |
| B9 | Uptime Kuma widget on Homepage shows "–" | Configured with an API key, but the widget needs the `slug` of a status page, and none exists | Dashboard shows no monitoring data | Create a status page and use its slug |
| B10 | Template leftovers on Homepage | Default *Developer / Social / Entertainment* bookmarks; extra `}` in `custom.css` | Unprofessional dashboard | Clean config |
| B11 | False outages | All monitors use `maxretries = 0`: one failed check = DOWN (e.g. n8n during start-up) | Noise, unnecessary restarts | 2–3 retries before DOWN |
| B12 | Duplicated blocklist | StevenBlack list added twice in Pi-hole | Wasted gravity update time | Remove duplicate |
| B13 | Scheduled jobs never ran on their own | Backup and daily report use the default schedule (00:00) while the VMs were usually off at night | Daily automations mostly ran manually | Schedule at times the lab is up, or run the lab 24/7 |

## Security weaknesses

| # | Weakness | Why it matters | Fix in v2 |
|---|---|---|---|
| S1 | **Unauthenticated webhooks** | Anyone on the network can `POST /webhook/kuma-alert` to restart containers on demand (DoS) or forge Fail2Ban alerts | Header auth / HMAC on every webhook, allow-list source IPs |
| S2 | **docker-socket-proxy with `CONTAINERS=1` + `POST=1`** | Allows any POST on the containers API, including **creating** a privileged container that mounts the host filesystem → root on PC2 | Allow only restarts (`ALLOW_RESTARTS=1`, `POST=0`) |
| S3 | **Docker socket mounted** in Portainer (rw) and Homepage (ro) | rw = full control of the host; even read-only exposes every container's environment, including database passwords | Remove from Homepage; Portainer behind auth/VPN or removed |
| S4 | **No TLS anywhere** | n8n, Kuma, Homepage, Nextcloud and Pi-hole run over HTTP; `N8N_SECURE_COOKIE=false`. Credentials travel in clear text | Reverse proxy with TLS (Caddy/Traefik), secure cookies |
| S5 | **Host firewall disabled** | UFW installed but inactive on both VMs: every service is open to the whole network | Default-deny firewall, expose only what each role needs |
| S6 | **Password SSH + root-equivalent backup user** | SSH accepts passwords; `securenet-backup` is in the `docker` group (≈ root) and its password is stored in n8n | Key-based SSH only; backup via a restricted command, not a docker-group user |
| S7 | **Secrets in plain text** | Pi-hole password inside a workflow, Kuma API key in Homepage config, n8n encryption key inline in Compose, the VPN client's private key left on the server, `NODE_FUNCTION_ALLOW_BUILTIN=fs` enabled | `.env` / Docker secrets, n8n credentials for everything, rotate all keys, keys generated on the client |
| S8 | **Unpinned, outdated images** | Every image uses `:latest` (8–10 months old); Pi-hole, Portainer and Uptime Kuma had pending updates; Nextcloud 29 is out of support | Pin versions, update policy, automated update checks |

## Design limitations

| # | Limitation | Detail |
|---|---|---|
| D1 | The VPN did not prove remote access | The client sat on the same network as the server, and `AllowedIPs = 10.0.0.0/24` sent lab traffic (services, Pi-hole DNS) **outside** the tunnel. v2: client on a separate network, `AllowedIPs` including `192.168.2.0/24`, so services are reachable *only* through the VPN |
| D2 | Pi-hole protected almost nobody | Neither PC1 nor PC2 used it as their resolver; only the VPN client did, so stats were close to zero (29 queries, 0 blocked) |
| D3 | Backups were incomplete and short-lived | Only Nextcloud and n8n data; nothing from PC1, Kuma, Homepage or Compose. Temporary AWS Academy credentials expire; local `.enc` copies are never pruned; restore not automated |

## What was done right

The review is not only bad news. Several decisions held up well:

- n8n reaches Docker through a **socket proxy**, not the raw socket.
- Backups are **encrypted before leaving the host** (AES-256 + PBKDF2), with the passphrase in a `600` file and DB credentials read from the container.
- **Portable network design** (host-only + NAT), independent of the physical network.
- **Persistent, recoverable n8n** (external volume, fixed encryption key).
- **Input normalisation and de-duplication** in the self-healing workflow, which also flags unmapped events instead of dropping them.
- Fail2Ban keeps its native ban and adds alerting on top.

## v2 roadmap

These findings are the backlog for **SecureNet v2**, which will be developed in its own repository:

1. Fix B1–B13 and verify each fix with evidence.
2. Harden: webhook auth, minimal socket proxy, TLS reverse proxy, firewall, key-only SSH, secrets management, pinned images (S1–S8).
3. Real remote-access VPN demo and Pi-hole as the lab resolver (D1–D2).
4. Complete, monitored backups with automated restore tests (D3).
5. New capabilities on top of a solid base.
