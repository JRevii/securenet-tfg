# n8n Workflows

This folder is intended for n8n workflow exports.

Before committing an exported workflow:

- Remove credentials.
- Remove Telegram tokens.
- Remove webhook production URLs if private.
- Replace internal secrets with placeholders.
- Confirm that no password appears in JSON nodes.

Suggested workflows:

- `fail2ban-alert.json`
- `service-health-recovery.json`
- `encrypted-backup-report.json`
- `network-scan-alert.json`
- `dns-hourly-summary.json`
- `daily-security-report.json`
