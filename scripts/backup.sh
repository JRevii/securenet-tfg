#!/bin/bash
set -euo pipefail

# =======================
# SecureNet Backup Script
# =======================

DATE="$(date +%F_%H-%M-%S)"
BACKUP_BASE="/opt/securenet/backups"
TMP_DIR="$BACKUP_BASE/tmp/$DATE"
LOG_DIR="$BACKUP_BASE/logs"
LOG_FILE="$LOG_DIR/backup_$DATE.log"

# S3
S3_BUCKET="s3://<YOUR_S3_BUCKET>"
S3_PREFIX="daily"

# Docker names (según tu infraestructura)
DB_CONTAINER="nextcloud-db"
NEXTCLOUD_DATA_VOL="securenet_nextcloud_data"
N8N_DATA_VOL="securenet_n8n_data"   # recomendado
# Si NO quieres backup de n8n, comenta el bloque [3/6]

# Cifrado AES-256 (NO pongas la password en el script)
ENC_PASS_FILE="/opt/securenet/.enc_pass"

mkdir -p "$TMP_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== SecureNet Backup START: $DATE ==="

# Comprobar fichero de password de cifrado
if [ ! -f "$ENC_PASS_FILE" ]; then
  echo "ERROR: No existe $ENC_PASS_FILE (password de cifrado)."
  echo "Crea el fichero con: sudo bash -c 'echo \"TU_PASSWORD\" > /opt/securenet/.enc_pass' && sudo chmod 600 /opt/securenet/.enc_pass"
  exit 1
fi

# 1) Dump MariaDB usando usuario MYSQL_USER (sin root)
echo "[1/6] Dump MariaDB (Nextcloud)..."
DB_NAME="$(docker exec "$DB_CONTAINER" printenv MYSQL_DATABASE)"
DB_USER="$(docker exec "$DB_CONTAINER" printenv MYSQL_USER)"
DB_PASS="$(docker exec "$DB_CONTAINER" printenv MYSQL_PASSWORD)"

docker exec -e MYSQL_PWD="$DB_PASS" "$DB_CONTAINER" \
  mariadb-dump -u "$DB_USER" --single-transaction --routines --triggers --events "$DB_NAME" \
  > "$TMP_DIR/nextcloud_db_$DATE.sql"

# 2) Backup volumen Nextcloud data
echo "[2/6] Backup Nextcloud volume..."
docker run --rm \
  -v "$NEXTCLOUD_DATA_VOL":/data:ro \
  -v "$TMP_DIR":/backup \
  alpine sh -c "cd /data && tar -czf /backup/nextcloud_data_$DATE.tar.gz ."

# 3) Backup volumen n8n (recomendado)
echo "[3/6] Backup n8n volume..."
docker run --rm \
  -v "$N8N_DATA_VOL":/data:ro \
  -v "$TMP_DIR":/backup \
  alpine sh -c "cd /data && tar -czf /backup/n8n_data_$DATE.tar.gz ."

# 4) Empaquetar todo a un único tar.gz
echo "[4/6] Packaging..."
FINAL_TAR="$BACKUP_BASE/securenet_backup_$DATE.tar.gz"
tar -czf "$FINAL_TAR" -C "$TMP_DIR" .

# 5) Cifrado AES-256 + PBKDF2
echo "[5/6] Encrypt (AES-256-CBC + PBKDF2)..."
FINAL_ENC="$FINAL_TAR.enc"

openssl enc -aes-256-cbc -salt -pbkdf2 \
  -in "$FINAL_TAR" -out "$FINAL_ENC" \
  -pass file:"$ENC_PASS_FILE"

# 6) Subida a S3
echo "[6/6] Upload to S3..."
aws s3 cp "$FINAL_ENC" "$S3_BUCKET/$S3_PREFIX/"

# Limpieza
rm -rf "$TMP_DIR"
rm -f "$FINAL_TAR"

echo "=== Backup OK: $(basename "$FINAL_ENC") uploaded to $S3_BUCKET/$S3_PREFIX/ ==="
exit 0
