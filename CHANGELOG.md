# Changelog

## v1.1 (final) — 2026-11-19

Closes the rest of the [post-delivery review](docs/08-security-review.md) that can be fixed inside v1. Every fix was applied to the running lab and verified. Evidence and test details are in the review, under *Fixed in v1.1 final*.

### Security

- **S1 — authenticated webhooks.** `kuma-alert` and `fail2ban` need a key in the `X-SecureNet-Key` header (Header Auth, one key per sender) and come from an allowed IP. The keys were generated on the servers and copied into n8n through pipes, so they were never shown. Without a key, with a wrong key, or with the right key from another IP, the webhook answers **403**. Real bans and real Kuma alerts still go through. The old `UptimeKumaN8N` workflow is deleted.
- **S5 — firewall.** UFW is default-deny on both VMs, and SSH was allowed before UFW was enabled. On PC2, Docker's published ports are filtered in `DOCKER-USER`, because Docker bypasses UFW. Tested with an address outside the lab: Docker ports and SSH are dropped and logged; the lab still has access.
- **S6 — key-only SSH** on both VMs, with no root login. The backup user is no longer in the `docker` group and has no password. n8n runs the backup with a forced-command key and a single `sudo` rule.
- **S7 — secrets out of the clear.**
  - Compose secrets moved to `.env` (root, 600). n8n no longer allows the `fs` module.
  - Pi-hole uses its own app password stored in an n8n credential. The admin password was rotated because it had been exposed.
  - The Kuma API keys are revoked. The WireGuard key files are now 600.
- **S3 — Docker socket.** Homepage reads container status through its own read-only socket proxy, on an internal network. Portainer is stopped by default and serves HTTPS only.
- **S8 —** every image is pinned to the exact version that was running.

### Fixed

- **B1** — no stray `=` in messages. Every Telegram message is now sent as escaped HTML (see B17).
- **B2** — the network scanner keeps a MAC baseline and alerts only on new devices. The scan is written atomically, and a stale scan raises an error.
- **B3** — the daily report counts real bans and outages from a shared event log.
- **B4** — the backup reports its real exit status and cleans up its plain-text temp files. A failure is announced as a failure.
- **B5** — explicit DOWN/UP/INFO/INVALID routing. An outage is never announced as "recovered", and Nextcloud is now auto-restarted.
- **B7** — de-duplication now actually works (*Remove Duplicates* node).
- **B8** — clean Pi-hole/Docker HTTP calls; Pi-hole sessions are logged out after each run.
- **B9** — status page `securenet` in Uptime Kuma; the Homepage widget shows real data.
- **B10** — Homepage rebuilt. [Screenshot](assets/screenshots/homepage-dashboard-v1.1.png).
- **B12** — duplicate blocklist removed. Two blocklists had been added as **allow** lists; they are block lists again (68k → 280k domains).
- **B13** — the backup runs at 20:30 and the report at 21:00, when the lab is usually up.
- **D2** — both VMs resolve DNS through Pi-hole.
- **B14** — the INCIDENT alert never arrived (first seen in the 18/10/2026 demo, tracked in the SecureNet v2 backlog). The original hypothesis was broken Markdown. The confirmed cause: the restart node treated Docker's `204 No Content` as an error, so the outage alert was never sent. Markdown was also breaking some messages (B17).
- **B16 (new)** — *Pi-hole Stats* still pointed to a deleted Telegram credential. The v1.1 fix had only worked in a manual run.
- **B17 (new)** — Telegram parsed messages as Markdown, so any `_` broke them, including the error-handler alert itself.

### Still open

- **Backups cannot reach S3**: the AWS Academy credentials expired (`ExpiredToken`). The workflow now reports this correctly. New credentials are needed.
- S4 (TLS), D1 (VPN from a separate network), D3 (complete backups, restore tests) and the single-host limitation are planned for v2.

## v1.1 — 2026-11-13

Fixes from the [post-delivery security review](docs/08-security-review.md), prompted by two questions from a reviewer: *"If n8n goes down, who sends the alert?"* and *"How does n8n reach the Docker API?"*. Every change was applied to the running lab and verified. The graded version is tagged `v1.0-tfg`.

### Fixed

- **B15 (new) — n8n was a single point of failure.** Every alert went through n8n, so an n8n outage was silent. Uptime Kuma now sends Telegram alerts **directly**, with its own bot. Tested with `docker stop n8n`: alert in under a minute.
- **B6 — wrong webhook on the n8n monitor.** It sent `monitor_code: HOMEPAGE` and a literal `"..."`. The webhook was removed from that monitor, which now checks `/healthz`.
- **B11 — false outages.** 2 retries on every monitor before marking a service as down.
- **S2 — socket proxy allowed creating containers (≈ root on PC2).** The proxy now allows only listing and restarting: `CONTAINERS=1`, `POST=0`, `ALLOW_RESTARTS=1`. Tested from inside n8n: create → 403, restart → OK, list → OK. Self-healing still works.

### Added

- **Error workflow** ([`workflows/07-error-handler.json`](workflows/07-error-handler.json)): if any workflow fails, n8n sends a Telegram alert with the workflow, node and error. Tested with a scheduled workflow that throws on purpose. In its first hour it caught a real failure: after rotating the Telegram tokens, *Pi-hole Stats* still pointed to a deleted credential and would have failed silently. Fixed by reassigning the credential.

### Changed

- **Socket proxy image:** `tecnativa/docker-socket-proxy` → `lscr.io/linuxserver/socket-proxy`. With Tecnativa's image, restarts were also rejected (403) when `POST=0`, even after updating, which broke self-healing. The LinuxServer image accepts the same variables and the container keeps its name, so n8n needed no changes.
- **Telegram:** all bot tokens rotated; one bot for Uptime Kuma and another for n8n, so a leaked token only affects one channel.

### Still open (at the time)

- **S1** (webhook authentication): next. *(Done in v1.1 final.)*
- Everything still runs on one host: if PC2 goes down, nobody is alerted. Planned for SecureNet v2 (external watchdog in AWS).
- The rest of the review (B1–B5, B7–B10, B12–B14, S3–S8, D1–D3) is tracked for v1.1 follow-ups or v2. *(See v1.1 final.)*
