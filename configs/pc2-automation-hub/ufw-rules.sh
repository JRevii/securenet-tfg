#!/bin/bash
# PC2 (automation hub), as root. S5: default-deny firewall + DOCKER-USER filtering,
# because Docker publishes ports through its own iptables chains and skips UFW.
set -euo pipefail
LAB=192.168.2.0/24
VPN=10.0.0.0/24
DOCKERNET=172.18.0.0/16     # "securenet" compose network

ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw default deny routed

# SSH first
ufw allow from $LAB to any port 22 proto tcp comment 'SSH from lab'
ufw allow from $VPN to any port 22 proto tcp comment 'SSH from VPN'
# n8n -> backup user (key restricted to one command and to this network)
ufw allow from $DOCKERNET to any port 22 proto tcp comment 'n8n backup over SSH'
# Containers that reach published ports via 192.168.2.20 go through docker-proxy on
# the host (INPUT chain): Kuma monitors, the Kuma webhook to n8n, Homepage widgets
ufw allow from $DOCKERNET to any port 3000,3001,5678,8080,9443 proto tcp comment 'containers -> published ports'

# Published Docker ports: only the lab and the VPN may open new connections
AFTER=/etc/ufw/after.rules
if ! grep -q 'SecureNet DOCKER-USER' $AFTER; then
  cp -a $AFTER /root/backups/after.rules.$(date +%Y%m%d-%H%M%S)
  cat >> $AFTER <<EOF

# --- SecureNet DOCKER-USER (S5): Docker skips UFW for published ports ---
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i br-+ -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -s $LAB -j RETURN
-A DOCKER-USER -s $VPN -j RETURN
-A DOCKER-USER -m conntrack --ctstate NEW -j LOG --log-prefix "[DOCKER-USER BLOCK] " -m limit --limit 3/min
-A DOCKER-USER -m conntrack --ctstate NEW -j DROP
-A DOCKER-USER -j RETURN
COMMIT
EOF
fi

systemd-run --quiet --unit=ufw-rollback --on-active=180 /bin/sh -c "/usr/sbin/ufw disable; iptables -F DOCKER-USER"
ufw --force enable
echo "ufw enabled, rollback armed (180 s)"
ufw status verbose
echo "--- DOCKER-USER"; iptables -S DOCKER-USER
