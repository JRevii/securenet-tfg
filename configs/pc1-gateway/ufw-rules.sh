#!/bin/bash
# PC1 (security gateway), as root. S5: default-deny firewall.
set -euo pipefail
LAB=192.168.2.0/24
VPN=10.0.0.0/24

chmod 600 /etc/wireguard/*        # S7: key files were 644

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# SSH first, so enabling the firewall can never cut the admin session
ufw allow from $LAB to any port 22 proto tcp comment 'SSH from lab'
ufw allow in on wg0 from $VPN to any port 22 proto tcp comment 'SSH from VPN'

# Pi-hole: DNS + web/API (Homepage widget, n8n stats, Kuma monitor)
for src in $LAB $VPN; do
  ufw allow from $src to any port 53 comment 'DNS (Pi-hole)'
  ufw allow from $src to any port 80 proto tcp comment 'Pi-hole web/API'
done

# WireGuard endpoint + forwarding VPN clients into the lab
ufw allow 51820/udp comment 'WireGuard'
ufw route allow in on wg0 out on enp0s3 comment 'VPN clients -> lab'

systemd-run --quiet --unit=ufw-rollback --on-active=180 /usr/sbin/ufw disable
ufw --force enable
echo "ufw enabled, rollback armed (180 s)"
ufw status verbose
