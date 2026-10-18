#!/bin/bash
OUT="/opt/n8n-files/scan.txt"
DATE=$(date "+%Y-%m-%d %H:%M:%S")

echo "=== SecureNet scan $DATE ===" > "$OUT"
# -sn: ping scan, -PR: ARP en LAN (mejor para MACs)
nmap -sn -PR 192.168.2.0/24 >> "$OUT"
