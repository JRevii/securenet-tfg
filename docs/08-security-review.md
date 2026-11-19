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

## Fixed in v1.1 (November 2026)

After publishing the project, a reviewer asked two questions: *"If n8n goes down, who sends the alert?"* and *"How does n8n reach the Docker API?"*. Both pointed at real gaps. These fixes were applied to the running lab and verified; the analysis above is kept as it was.

| # | Fix | Evidence |
|---|---|---|
| B15 (new) | n8n was a single point of failure: every alert went through it. Uptime Kuma now notifies Telegram **directly**, with its own bot | `docker stop n8n` → Kuma alert in under a minute ([screenshot](../assets/screenshots/telegram-kuma-direct-alerts.png)) |
| B6 | Removed the webhook on the n8n monitor (it sent `HOMEPAGE` and `"..."`); the monitor checks `/healthz` | Stopping/starting n8n produces only Kuma's Down/Up messages |
| B11 | 2 retries on every monitor | No false outage while n8n starts |
| S2 | Socket proxy limited to list + restart (`POST=0`, `ALLOW_RESTARTS=1`), image switched to `linuxserver/socket-proxy` | create → 403, restart → OK, list → OK ([screenshot](../assets/screenshots/proxy-403-test.png)); self-healing still works ([screenshot](../assets/screenshots/telegram-n8n-recovered-via-proxy.png)) |
| New | Error workflow ([07-error-handler.json](../workflows/07-error-handler.json)): any failed workflow sends a Telegram alert | A scheduled test workflow that throws → alert with workflow, node and error. First real catch: *Pi-hole Stats* pointing to a deleted Telegram credential after the token rotation |
| — | Telegram tokens rotated; one bot for Kuma, another for n8n | — |

Still open at that point: S1 (webhook authentication) was next (done below); everything still runs on one host, so if PC2 itself goes down nobody is alerted (v2: external watchdog in AWS).

## Fixed in v1.1 final (19 November 2026)

Same rule as before: every row was applied to the running lab and verified there. Telegram delivery was checked in n8n's execution data (the Telegram node finished successfully) and in Uptime Kuma's logs.

### Security

| # | Fix | How it was verified |
|---|---|---|
| S1 | Both webhooks require Header Auth (`X-SecureNet-Key`), with **one key per sender**, plus an IP allow-list: `192.168.2.10` for `fail2ban`, and the Docker bridge gateway `172.18.0.1` for `kuma-alert` (Kuma reaches n8n through the published port, so docker-proxy rewrites the source). The keys were generated on the servers (`openssl rand`, root 600) and piped into n8n credentials and into Kuma's headers, never displayed. Fail2Ban passes its key to curl through stdin, so it stays out of the config file and `ps`. The legacy `UptimeKumaN8N` workflow is deleted. | No key → 403, wrong key → 403 (from the allowed IP), right key from a non-allowed IP → 403, right key + allowed IP → 200. Real ban (`fail2ban-client set sshd banip`) → alert sent. `docker stop homepage` → Kuma → n8n → restart → alert. `/webhook/uptimekuma` → 404 |
| S5 | UFW `deny incoming` on both VMs, with SSH allowed first. PC1 only accepts SSH, DNS and Pi-hole web from the lab and the VPN, plus WireGuard and VPN→lab forwarding. PC2 adds SSH from the Docker network (backup) and container→published-port traffic. **Docker publishes ports through its own iptables chains and skips UFW**, so `DOCKER-USER` (in `/etc/ufw/after.rules`) only lets the lab and the VPN open new connections to containers. Applied with a 3-minute automatic rollback. | From a temporary non-lab address on PC1 (masquerading disabled for it, return route added on PC2): 3000/5678/8080 → no answer, logged as `[DOCKER-USER BLOCK]`; 22 → `[UFW BLOCK]`. From the lab: everything answers. New SSH session works |
| S6 | `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `AuthenticationMethods publickey`, `PermitRootLogin no` in `00-securenet-hardening.conf`, loaded before cloud-init's file (first value wins). The backup user is out of the `docker` group and its password is locked. n8n uses an ed25519 key with `restrict,from="172.18.0.0/16",command="sudo -n /opt/securenet/backup.sh"`, and a single sudo rule allows that script. The private key went straight from PC2 into an n8n credential and was shredded on PC2. | Key login checked in a second session before cancelling the rollback; `ssh -o PubkeyAuthentication=no` → `Permission denied (publickey)` on both VMs. The backup runs from n8n with the key (through UFW) |
| S7 | Compose secrets moved to `/root/securenet/.env` (root 600). `NODE_FUNCTION_ALLOW_BUILTIN=fs` removed from n8n. Pi-hole: **admin password rotated** (it was exposed during this work), and n8n uses a separate Pi-hole *app password* stored as a Custom Auth credential, instead of the admin password inside the workflow. Homepage keys only as `HOMEPAGE_VAR_*`. All Uptime Kuma API keys revoked. WireGuard key files set to 600 | `docker exec n8n printenv NODE_FUNCTION_ALLOW_BUILTIN` → unset. The exported workflows contain no password, token, chat ID or credential ID (checked by the export script) |
| S3 | Homepage no longer mounts `/var/run/docker.sock`: it gets the container list from a **second** socket proxy (`CONTAINERS=1`, `POST=0`, no restarts) on an `internal: true` network that only it can reach. n8n's proxy is not shared. Portainer (read-write socket) is in a `manual` profile: stopped by default, HTTPS only (`9000` removed), and its Kuma monitor is paused | `homepage-docker` network: internal, containing only `homepage` and `homepage-socket-proxy`. Status dots work |
| S8 | Every image pinned to the exact version that was running, by tagging the local image, so nothing was upgraded by surprise: n8n 2.4.4, Uptime Kuma 1.23.17, Homepage v1.10.1, Portainer 2.33.6, MariaDB 11.8.6, Nextcloud 29.0.16, socket-proxy 3.4.7-r0-ls105 | `docker ps` shows the pinned tags |

### Functional

| # | Root cause confirmed | Fix | How it was verified |
|---|---|---|---|
| B5 | Execution 446: a PIHOLE `DOWN` (no container) became `ERROR` and went out the IF's false branch, and the user got "SERVICIO RECUPERADO". Kuma test messages (`INFO`) did the same | A *Classify* node sets an explicit action: `RESTART`, `ALERT` (alert only: Pi-hole is on PC1, or unknown monitor), `RECOVERED`, `INFO` or `INVALID`. Nextcloud is mapped; n8n and Kuma are never restarted. Kuma now sends its real heartbeat `status` (0/1) and an escaped `msg` (`{{ msg \| json }}`) | Synthetic DOWN/UP/INFO/INVALID events from the Kuma container, plus a real `docker stop homepage`: each one gives the right message |
| B7 | All 16 stored executions left `If drop` through the *true* branch: `"false "` (trailing space) compared loosely with `true` is true. Also, `staticData` was `null` in the database: n8n 2.x runs Code nodes in a task runner and does not persist `$getWorkflowStaticData` from them, so de-duplication never had any memory | *Remove Duplicates* node (history kept in n8n's database) on `monitor\|status\|time window` | Two identical DOWNs 3 s apart: the second stops at *Drop duplicates* |
| B8 | Header name `" X-FTL-CSRF"`, SID with a leading space, restart URL ending in `\n` | Clean `X-FTL-SID` only (CSRF is not needed with header auth); logout after each run; clean URL | Pi-hole run OK; only a few short-lived sessions remain in Pi-hole |
| B1 | `"={{ ... }}"` inside an expression, and templates starting with `=={{` | No nested markers; messages are built as plain text and HTML-escaped | Messages without `=` |
| B4 | The Code node looked for `EXIT_CODE:`, which the script never printed, and the message ignored the result. Failed runs also left plain-text DB dumps in `tmp/` | `backup.sh` checks the AWS credentials first, cleans up in an `EXIT` trap, uses `umask 077` and always prints `EXIT_CODE:n`. The workflow reports OK/FAILED and has an SSH error branch | Run from n8n: **"Backup FALLIDO, exit 3, AWS credentials expired"** instead of "OK" |
| B3 | The counters lived in WF6's own static data, which nothing else could write to | WF2 and WF5 append to `/home/node/.n8n-files/events.jsonl`; WF6 counts today's lines | Report showed 3 bans / 5 outages / last service Homepage, matching the tests |
| B2 | WF4 never compared against anything | `known_devices.json` baseline by MAC; alert only on new devices (first run: one baseline message). `scan.sh` writes atomically with an ISO timestamp; n8n reads at :05/:35 and rejects a scan older than 45 min | First run: baseline of 3; second run: no message |
| B9 | No status page existed | Status page `securenet` (dark, grouped by machine) used by the Homepage widget | Widget shows sites up/down; [screenshot](../assets/screenshots/uptime-kuma-status-page.png) |
| B10 | Template bookmarks, stray `}` | Homepage rebuilt: four groups with icons, real Pi-hole v6 / Uptime Kuma / Nextcloud (read-only serverinfo token) widgets, status dots, generated background and favicon | [Screenshot](../assets/screenshots/homepage-dashboard-v1.1.png), no "Missing" or "API Error" |
| B12 | List 1 was StevenBlack as a block list. Lists 2–4 (StevenBlack again, AdguardDNS, KADhosts) were **allow** lists (`type=1`): instead of blocking those domains, they let them through | Duplicate removed; AdguardDNS and KADhosts re-added as block lists | Gravity: 68,449 → 279,806 unique domains; `doubleclick.net` → `0.0.0.0` |
| B13 | Default 00:00 schedules while the VMs were off | Backup at 20:30, report at 21:00 (Europe/Madrid), scanner at :05/:35 | Schedules visible through the API |
| D2 | PC1 and PC2 used 8.8.8.8 | netplan: Pi-hole first, 1.1.1.1 only as fallback (so Kuma can still reach Telegram if PC1 dies); the NAT adapter no longer injects DNS. Applied with an automatic rollback | Pi-hole went from 0 to 74 queries in minutes; `doubleclick.net` blocked from PC2 |
| B14 | The INCIDENT alert never arrived (18/10/2026 demo; hypothesis: broken Markdown). Confirmed cause, executions 419/435/453: every restart ended in an error in the HTTP node (Docker answers `204 No Content`), so **the outage alert was never sent** | The node reads a text response and the message reports the real status code, or the failure | Real restart → `HTTP 204` in the alert |
| B16 (new) | *Pi-hole Stats* still pointed to a deleted credential. The v1.1 fix only worked in one manual run; scheduled runs kept failing | Credential reassigned in the saved workflow | Scheduled run OK |
| B17 (new) | The Telegram node sends Markdown; `monitor_code`, file names and error texts with `_` failed with *can't parse entities*, **including the error handler's own alert** | Every message is sent as HTML with `& < >` escaped | INVALID event and a test error containing `_ < > &` delivered |

### Still open

- **S3 upload**: the AWS Academy credentials expired on 18 Oct 2026 (`ExpiredToken`). The workflow now says so; new credentials are needed to get a green backup.
- **S4** TLS, **D1** VPN from a separate network, **D3** complete backups with restore tests, and the single-host problem: v2.
- Nextcloud 29 is end-of-life. It is pinned, not upgraded: a major-version upgrade needs its own plan.
- n8n's encryption key and the MariaDB passwords were moved, not rotated (rotating them means re-encrypting the credentials and changing database users).
- Uptime Kuma 1.x weights each heartbeat by the time since the previous one, so the first heartbeat after the VMs were powered off counts as a long outage (n8n showed 5 % with 0 DOWN beats). It corrects itself after 24 h of uptime.

## v2 roadmap

These findings are the backlog for **SecureNet v2**, which will be developed in its own repository:

1. Fix B1–B13 and verify each fix with evidence.
2. Harden: webhook auth, minimal socket proxy, TLS reverse proxy, firewall, key-only SSH, secrets management, pinned images (S1–S8).
3. Real remote-access VPN demo and Pi-hole as the lab resolver (D1–D2).
4. Complete, monitored backups with automated restore tests (D3).
5. New capabilities on top of a solid base.
