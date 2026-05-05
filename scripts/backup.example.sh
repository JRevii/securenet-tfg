#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="/opt/securenet/backups"
TMP_DIR="${BACKUP_ROOT}/tmp/securenet-$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${TMP_DIR}.tar.gz"
ENCRYPTED="${ARCHIVE}.enc"
PASSPHRASE_FILE="/opt/securenet/.enc_pass"
S3_BUCKET="${AWS_S3_BUCKET:-your-bucket-name}"

mkdir -p "$TMP_DIR"

echo "[+] Collecting configuration files"
# Add safe export commands here. Do not copy secrets unless they are encrypted.

echo "[+] Creating archive"
tar -czf "$ARCHIVE" -C "$TMP_DIR" .

echo "[+] Encrypting archive"
openssl enc -aes-256-cbc -salt -pbkdf2 \
  -in "$ARCHIVE" \
  -out "$ENCRYPTED" \
  -pass "file:${PASSPHRASE_FILE}"

echo "[+] Uploading to S3"
aws s3 cp "$ENCRYPTED" "s3://${S3_BUCKET}/daily/"

echo "[+] Cleaning temporary files"
rm -rf "$TMP_DIR" "$ARCHIVE" "$ENCRYPTED"

echo "[+] Backup completed"
