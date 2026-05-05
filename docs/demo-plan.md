# Demo Plan

This document describes safe demo scenarios for SecureNet.

## Demo 1 - DNS Filtering

Goal: prove that Pi-hole is working as the DNS filtering layer.

Steps:

1. Configure a test client to use Pi-hole as DNS.
2. Generate normal DNS traffic.
3. Visit a known blocked test domain or use a controlled blocklist entry.
4. Show the query in Pi-hole statistics.

Expected result:

- DNS queries appear in Pi-hole.
- Blocked domains are recorded.

## Demo 2 - VPN Access

Goal: prove that the internal lab network is only reachable through WireGuard.

Steps:

1. Try to reach the internal lab IP with VPN disabled.
2. Enable WireGuard.
3. Ping or access an internal service.
4. Confirm the route uses the VPN tunnel.

Expected result:

- Internal access fails without VPN.
- Internal access works with VPN.

## Demo 3 - Service Monitoring

Goal: prove that Uptime Kuma detects outages.

Steps:

1. Monitor a Docker service.
2. Stop the container in a controlled way.
3. Confirm Uptime Kuma marks it as down.
4. Restart the service and verify recovery.

Expected result:

- Downtime and recovery are visible in the monitoring dashboard.

## Demo 4 - Encrypted Backup

Goal: prove that backups are encrypted before external storage.

Steps:

1. Run the backup script.
2. Confirm the `.enc` archive is created.
3. Upload it to the configured S3 bucket.
4. Test decryption in a controlled restore folder.

Expected result:

- Backup completes.
- Encrypted archive can be restored with the passphrase file.
