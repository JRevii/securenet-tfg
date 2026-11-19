#!/bin/bash
# =======================================================================
# SecureNet backup: MariaDB dump + Docker volumes -> AES-256 -> AWS S3
# =======================================================================
# v1.1
# - B4: the script always ends with "EXIT_CODE:<n>" and n8n decides success
#   from it; a failed run is reported, never announced as OK.
# - B4: temporary files (plain-text DB dump and archive) are removed on every
#   exit path through a trap, and files are created with umask 077.
# - B4: AWS credentials are checked before doing any heavy work.
# - S6: runs as root through a single sudo rule, triggered by n8n over SSH with
#   a key whose authorized_keys entry forces this command. The backup user is
#   no longer in the docker group and has no password.
# - Site settings (bucket name, AWS profile files) live in backup.env, not here.
set -euo pipefail
umask 077

CONF="/opt/securenet/backup.env"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"
: "${S3_BUCKET:?S3_BUCKET is not set in $CONF}"
S3_PREFIX="${S3_PREFIX:-daily}"
KEEP_LOCAL="${KEEP_LOCAL:-3}"                    # encrypted copies kept on disk
export AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-/opt/securenet/aws/credentials}"
export AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-/opt/securenet/aws/config}"

DATE="$(date +%F_%H-%M-%S)"
BACKUP_BASE="/opt/securenet/backups"
TMP_DIR="$BACKUP_BASE/tmp/$DATE"
LOG_DIR="$BACKUP_BASE/logs"
LOG_FILE="$LOG_DIR/backup_$DATE.log"
ENC_PASS_FILE="/opt/securenet/.enc_pass"        # AES passphrase, root:root 600

DB_CONTAINER="nextcloud-db"
NEXTCLOUD_DATA_VOL="securenet_nextcloud_data"
N8N_DATA_VOL="securenet_n8n_data"

FINAL_TAR="$BACKUP_BASE/securenet_backup_$DATE.tar.gz"
FINAL_ENC="$FINAL_TAR.enc"

finish() {
  local rc=$?
  rm -rf "$TMP_DIR"
  rm -f "$FINAL_TAR"                              # never leave a plain-text archive
  [ "$rc" -ne 0 ] && echo "=== SecureNet Backup FAILED (exit $rc) ==="
  echo "EXIT_CODE:$rc"
}
trap finish EXIT

mkdir -p "$TMP_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== SecureNet Backup START: $DATE ==="

[ -s "$ENC_PASS_FILE" ] || { echo "ERROR: missing $ENC_PASS_FILE (encryption passphrase)"; exit 2; }

echo "[0/6] Checking AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials are missing, invalid or expired ($AWS_SHARED_CREDENTIALS_FILE)"
  exit 3
fi

# 1) Dump MariaDB with the application user (not root); credentials are read
#    from the container and passed through the environment, never the command line
echo "[1/6] Dump MariaDB (Nextcloud)..."
DB_NAME="$(docker exec "$DB_CONTAINER" printenv MYSQL_DATABASE)"
DB_USER="$(docker exec "$DB_CONTAINER" printenv MYSQL_USER)"
DB_PASS="$(docker exec "$DB_CONTAINER" printenv MYSQL_PASSWORD)"
docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" \
  mariadb-dump -u "$DB_USER" --single-transaction --routines --triggers --events "$DB_NAME" \
  > "$TMP_DIR/nextcloud_db_$DATE.sql"
unset DB_PASS

echo "[2/6] Backup Nextcloud volume..."
docker run --rm -v "$NEXTCLOUD_DATA_VOL":/data:ro -v "$TMP_DIR":/backup \
  alpine sh -c "cd /data && tar -czf /backup/nextcloud_data_$DATE.tar.gz ."

echo "[3/6] Backup n8n volume..."
docker run --rm -v "$N8N_DATA_VOL":/data:ro -v "$TMP_DIR":/backup \
  alpine sh -c "cd /data && tar -czf /backup/n8n_data_$DATE.tar.gz ."

echo "[4/6] Packaging..."
tar -czf "$FINAL_TAR" -C "$TMP_DIR" .

echo "[5/6] Encrypt (AES-256-CBC + PBKDF2)..."
openssl enc -aes-256-cbc -salt -pbkdf2 -in "$FINAL_TAR" -out "$FINAL_ENC" -pass file:"$ENC_PASS_FILE"
rm -f "$FINAL_TAR"

echo "[6/6] Upload to S3..."
aws s3 cp --only-show-errors "$FINAL_ENC" "$S3_BUCKET/$S3_PREFIX/"

# Keep only the newest $KEEP_LOCAL encrypted copies on disk
ls -1t "$BACKUP_BASE"/securenet_backup_*.tar.gz.enc 2>/dev/null | tail -n +"$((KEEP_LOCAL + 1))" | xargs -r rm -f

echo "=== Backup OK: $(basename "$FINAL_ENC") uploaded to $S3_BUCKET/$S3_PREFIX/ ==="
exit 0
