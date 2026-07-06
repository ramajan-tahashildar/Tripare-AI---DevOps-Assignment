-- Migration 002: booking_events table
-- Append-only event log for every state transition on a booking.

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL     PRIMARY KEY,
    booking_id UUID          NOT NULL,
    event_type VARCHAR(100)  NOT NULL,
    payload    JSONB,
    created_at TIMESTAMP     NOT NULL DEFAULT NOW(),

    -- Referential integrity: every event must belong to a known booking
    CONSTRAINT fk_booking
        FOREIGN KEY (booking_id)
        REFERENCES hotel_bookings (id)
        ON DELETE CASCADE,

    -- Enforce known event types
    CONSTRAINT chk_valid_event_type CHECK (
        event_type IN (
            'BOOKING_CREATED',
            'BOOKING_CONFIRMED',
            'BOOKING_CANCELLED',
            'BOOKING_COMPLETED',
            'PAYMENT_RECEIVED',
            'PAYMENT_FAILED',
            'NO_SHOW_RECORDED',
            'BOOKING_MODIFIED'
        )
    )
);

COMMENT ON TABLE  booking_events            IS 'Immutable audit log of every booking state transition';
COMMENT ON COLUMN booking_events.id         IS 'Auto-incrementing surrogate key';
COMMENT ON COLUMN booking_events.booking_id IS 'FK to hotel_bookings.id';
COMMENT ON COLUMN booking_events.event_type IS 'Type of event that occurred';
COMMENT ON COLUMN booking_events.payload    IS 'Arbitrary JSON metadata for the event';
COMMENT ON COLUMN booking_events.created_at IS 'When the event was recorded';
