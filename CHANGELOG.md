# Changelog

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

### Still open

- **S1** (webhook authentication): next.
- Everything still runs on one host: if PC2 goes down, nobody is alerted. Planned for SecureNet v2 (external watchdog in AWS).
- The rest of the review (B1–B5, B7–B10, B12–B14, S3–S8, D1–D3) is tracked for v1.1 follow-ups or v2.
