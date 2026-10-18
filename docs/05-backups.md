# 5 · Encrypted backups

Script: [`scripts/backup.sh`](../scripts/backup.sh) · on PC2: `/opt/securenet/backup.sh` · triggered daily by [workflow 3](04-workflows.md#3--encrypted-backups-to-s3).

## What it does

```
[1] mariadb-dump of the Nextcloud database (as the app user, not root)
[2] tar.gz of the Docker volume securenet_nextcloud_data   (via a throw-away alpine container, read-only)
[3] tar.gz of the Docker volume securenet_n8n_data         (workflows + credentials)
[4] everything packed into securenet_backup_<date>.tar.gz
[5] openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:/opt/securenet/.enc_pass
[6] aws s3 cp → s3://<bucket>/daily/
```

Design choices:

- `set -euo pipefail`: any failing step aborts the run.
- **No password in the script**: the database credentials are read from the running container (`docker exec … printenv MYSQL_USER`), the encryption passphrase from `/opt/securenet/.enc_pass` (`chmod 600`).
- Each run writes a log to `/opt/securenet/backups/logs/`.
- Volumes are mounted **read-only** in the temporary container.

## Restore

```bash
openssl enc -d -aes-256-cbc -pbkdf2 \
  -in securenet_backup_<date>.tar.gz.enc -out restore.tar.gz \
  -pass file:/opt/securenet/.enc_pass
tar -xzf restore.tar.gz          # nextcloud_db_<date>.sql, nextcloud_data_<date>.tar.gz, n8n_data_<date>.tar.gz

# database
docker exec -i nextcloud-db sh -c 'mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' < nextcloud_db_<date>.sql
# volume
docker run --rm -v securenet_nextcloud_data:/data -v "$PWD":/b alpine sh -c "cd /data && tar -xzf /b/nextcloud_data_<date>.tar.gz"
```

## Setup notes

- Ubuntu 24.04 no longer ships the `awscli` apt package; AWS CLI v2 was installed with the official installer (`awscli-exe-linux-x86_64.zip`).
- The project used an **AWS Academy (Learner Lab)** account, whose credentials are temporary STS keys (`aws_session_token`). They expire with each lab session.
- n8n connects over SSH as `securenet-backup`; the script must be owned by that user (`chmod 750`) and the user must be in the `docker` group, otherwise n8n gets `Permission denied` (exit code 126).

## Limitations found later

- Temporary AWS credentials mean unattended backups stop working once the session expires.
- The Telegram message always says "Backup OK" (the workflow does not check the result).
- Only Nextcloud and n8n are backed up: PC1 (Pi-hole, Fail2Ban, WireGuard), Uptime Kuma, Homepage and the Compose file are not.
- Local encrypted copies are never pruned, and restores were tested manually, not automatically.

Details and fixes in the [security review](08-security-review.md).
