#!/usr/bin/env bash
# =============================================================================
# backup.sh — Create a timestamped PostgreSQL dump from the local Docker instance
# =============================================================================
set -euo pipefail

# ─── Configuration (override via environment variables) ───────────────────────
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-hoteldb}"
DB_USER="${DB_USER:-dbadmin}"
# Load from .env if present (never hardcode passwords)
if [ -f ".env" ]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi
DB_PASSWORD="${DB_PASSWORD:-}"  # must be set in .env or via environment
[ -z "${DB_PASSWORD}" ] && { echo "ERROR: DB_PASSWORD is not set. Create a .env file or export DB_PASSWORD."; exit 1; }
BACKUP_DIR="${BACKUP_DIR:-./backups}"

# ─── Derived values ───────────────────────────────────────────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
error(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# ─── Pre-flight checks ────────────────────────────────────────────────────────
command -v pg_dump &>/dev/null || error "pg_dump not found. Install postgresql-client."
command -v gzip    &>/dev/null || error "gzip not found."

mkdir -p "${BACKUP_DIR}" || error "Cannot create backup directory: ${BACKUP_DIR}"

log "Starting backup of database '${DB_NAME}' on ${DB_HOST}:${DB_PORT}"

# ─── Wait for PostgreSQL to be ready ─────────────────────────────────────────
MAX_WAIT=30
WAITED=0
until PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null; do
  if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
    error "PostgreSQL did not become ready after ${MAX_WAIT}s. Is Docker running?"
  fi
  log "Waiting for PostgreSQL... (${WAITED}/${MAX_WAIT}s)"
  sleep 2
  WAITED=$((WAITED + 2))
done

# ─── Perform the dump ─────────────────────────────────────────────────────────
log "Running pg_dump → ${BACKUP_FILE}"
PGPASSWORD="${DB_PASSWORD}" pg_dump \
  --host="${DB_HOST}" \
  --port="${DB_PORT}" \
  --username="${DB_USER}" \
  --dbname="${DB_NAME}" \
  --format=plain \
  --no-password \
  --verbose \
  2>>"${BACKUP_DIR}/backup_${TIMESTAMP}.log" \
  | gzip > "${BACKUP_FILE}"

# ─── Verify the dump is non-empty ─────────────────────────────────────────────
BACKUP_SIZE=$(stat -c%s "${BACKUP_FILE}" 2>/dev/null || stat -f%z "${BACKUP_FILE}")
if [ "${BACKUP_SIZE}" -lt 100 ]; then
  rm -f "${BACKUP_FILE}"
  error "Backup file is suspiciously small (${BACKUP_SIZE} bytes). Check log: ${BACKUP_DIR}/backup_${TIMESTAMP}.log"
fi

# ─── Cleanup old backups (keep last 7) ────────────────────────────────────────
KEEP=7
OLD_BACKUPS=$(ls -t "${BACKUP_DIR}/${DB_NAME}_"*.sql.gz 2>/dev/null | tail -n +$((KEEP + 1)))
if [ -n "${OLD_BACKUPS}" ]; then
  echo "${OLD_BACKUPS}" | xargs rm -f
  log "Removed old backups (keeping last ${KEEP})."
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
BACKUP_SIZE_HUMAN=$(du -sh "${BACKUP_FILE}" | cut -f1)
log "Backup completed successfully."
log "  File : ${BACKUP_FILE}"
log "  Size : ${BACKUP_SIZE_HUMAN}"
log "  Log  : ${BACKUP_DIR}/backup_${TIMESTAMP}.log"
echo ""
echo "BACKUP_FILE=${BACKUP_FILE}"   # machine-readable: allows callers to capture the path
