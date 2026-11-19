#!/bin/bash
# SecureNet network discovery (cron on PC2, every 30 min at :00 and :30).
# n8n (WF4) reads the result at :05 and :35 and compares it with known_devices.json.
#
# v1.1: write to a temp file and rename it, so n8n never reads a half-written scan,
#       and stamp the scan with an ISO-8601 time (with offset) so n8n can detect
#       a stale scan.
set -euo pipefail

OUT="/opt/n8n-files/scan.txt"
TMP="$(mktemp /opt/n8n-files/.scan.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

{
  echo "=== SecureNet scan $(date -Iseconds) ==="
  # -sn: host discovery only, -PR: ARP ping (reliable on a LAN and gives MACs)
  nmap -sn -PR 192.168.2.0/24
} > "$TMP"

chmod 644 "$TMP"
mv -f "$TMP" "$OUT"
