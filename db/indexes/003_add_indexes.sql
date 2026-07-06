-- Migration 003: Indexes for hotel_bookings and booking_events
-- ─────────────────────────────────────────────────────────────────────────────
-- Target query being optimised:
--
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM   hotel_bookings
--   WHERE  city       = 'delhi'
--     AND  created_at >= NOW() - INTERVAL '30 days'
--   GROUP  BY org_id, status;
--
-- Execution plan WITHOUT index:
--   Seq Scan → Filter on city + created_at → Hash Aggregate
--   Cost: O(n) for full table scan on every execution.
--
-- Index strategy — composite index on (city, created_at, org_id, status, amount):
--
--   1. city        — equality filter: narrows the scan dramatically for a
--                    large multi-city table.
--   2. created_at  — range filter: allows the index scan to stop at the
--                    30-day boundary without touching older rows.
--   3. org_id,     — INCLUDEd columns: PostgreSQL can satisfy the SELECT
--      status,        list and GROUP BY entirely from the index (index-only
--      amount         scan), skipping the heap entirely for matching rows.
--
-- Net effect: the planner can execute an index-only scan using only this
-- index, avoiding a sequential scan and a separate heap fetch.
-- ─────────────────────────────────────────────────────────────────────────────

-- Primary optimisation index (covers the target analytical query)
CREATE INDEX CONCURRENTLY IF NOT EXISTS
    idx_hotel_bookings_city_createdat
ON hotel_bookings (city, created_at)
INCLUDE (org_id, status, amount);

-- Supporting index for booking_events lookups by booking_id
-- Speeds up JOIN queries and CASCADE operations.
CREATE INDEX CONCURRENTLY IF NOT EXISTS
    idx_booking_events_booking_id
ON booking_events (booking_id);

-- Partial index: fast lookup of only PENDING bookings
-- Useful for dashboards / alerts showing bookings awaiting action.
CREATE INDEX CONCURRENTLY IF NOT EXISTS
    idx_hotel_bookings_pending
ON hotel_bookings (created_at DESC)
WHERE status = 'PENDING';

-- GIN index on booking_events.payload for JSONB key/value searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS
    idx_booking_events_payload_gin
ON booking_events USING GIN (payload);
