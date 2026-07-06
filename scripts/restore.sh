#!/usr/bin/env bash
# =============================================================================
# restore.sh — Restore a PostgreSQL dump into a fresh local database
# Usage:
#   ./scripts/restore.sh                          # restores latest backup
#   ./scripts/restore.sh backups/hoteldb_XYZ.sql.gz
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
RESTORE_DB_NAME="${RESTORE_DB_NAME:-${DB_NAME}_restore}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
error(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# ─── Pre-flight checks ────────────────────────────────────────────────────────
command -v psql    &>/dev/null || error "psql not found. Install postgresql-client."
command -v gunzip  &>/dev/null || error "gunzip not found."

# ─── Resolve backup file ──────────────────────────────────────────────────────
if [ $# -ge 1 ]; then
  BACKUP_FILE="$1"
else
  # Default: pick the most recent backup
  BACKUP_FILE=$(ls -t "${BACKUP_DIR}/${DB_NAME}_"*.sql.gz 2>/dev/null | head -1 || true)
  [ -z "${BACKUP_FILE}" ] && error "No backup files found in '${BACKUP_DIR}'. Run ./scripts/backup.sh first."
fi

[ -f "${BACKUP_FILE}" ] || error "Backup file not found: ${BACKUP_FILE}"

log "Restoring from: ${BACKUP_FILE}"
log "Target database: ${RESTORE_DB_NAME} on ${DB_HOST}:${DB_PORT}"

# ─── Wait for PostgreSQL to be ready ─────────────────────────────────────────
MAX_WAIT=30
WAITED=0
until PGPASSWORD="${DB_PASSWORD}" pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" &>/dev/null; do
  if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
    error "PostgreSQL not reachable after ${MAX_WAIT}s. Is Docker running? Try: docker compose up -d"
  fi
  log "Waiting for PostgreSQL... (${WAITED}/${MAX_WAIT}s)"
  sleep 2
  WAITED=$((WAITED + 2))
done

# ─── Drop and recreate the restore target database ────────────────────────────
log "Dropping database '${RESTORE_DB_NAME}' (if it exists)..."
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
  -d postgres \
  -c "DROP DATABASE IF EXISTS ${RESTORE_DB_NAME};" \
  --no-password -q

log "Creating fresh database '${RESTORE_DB_NAME}'..."
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
  -d postgres \
  -c "CREATE DATABASE ${RESTORE_DB_NAME} OWNER ${DB_USER};" \
  --no-password -q

# ─── Restore the dump ─────────────────────────────────────────────────────────
log "Restoring dump into '${RESTORE_DB_NAME}'..."
gunzip -c "${BACKUP_FILE}" | \
  PGPASSWORD="${DB_PASSWORD}" psql \
    --host="${DB_HOST}" \
    --port="${DB_PORT}" \
    --username="${DB_USER}" \
    --dbname="${RESTORE_DB_NAME}" \
    --no-password \
    -q

log "Restore completed."

# ─── Verification queries ─────────────────────────────────────────────────────
log "Running verification queries..."

echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESTORE VERIFICATION — ${RESTORE_DB_NAME}"
echo "════════════════════════════════════════════════════════"
echo ""

echo "── Table row counts ──────────────────────────────────"
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
  -d "${RESTORE_DB_NAME}" \
  --no-password \
  -c "
SELECT
  'hotel_bookings'  AS table_name, COUNT(*) AS row_count FROM hotel_bookings
UNION ALL
SELECT
  'booking_events', COUNT(*) FROM booking_events;
"

echo ""
echo "── Booking status distribution ───────────────────────"
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
  -d "${RESTORE_DB_NAME}" \
  --no-password \
  -c "
SELECT status, COUNT(*) AS bookings, SUM(amount) AS total_amount
FROM hotel_bookings
GROUP BY status
ORDER BY bookings DESC;
"

echo ""
echo "── Target optimised query (delhi, last 30 days) ──────"
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
  -d "${RESTORE_DB_NAME}" \
  --no-password \
  -c "
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status
ORDER BY org_id, status;
"

echo ""
echo "── Index presence check ──────────────────────────────"
PGPASSWORD="${DB_PASSWORD}" psql \
  -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" \
  -d "${RESTORE_DB_NAME}" \
  --no-password \
  -c "
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE tablename IN ('hotel_bookings','booking_events')
ORDER BY tablename, indexname;
"

echo ""
echo "════════════════════════════════════════════════════════"
log "Verification complete. Review the output above."
log "Source backup : ${BACKUP_FILE}"
log "Restored into : ${RESTORE_DB_NAME} @ ${DB_HOST}:${DB_PORT}"
