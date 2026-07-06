-- Migration 001: hotel_bookings table
-- Stores one record per hotel reservation.

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID          PRIMARY KEY,
    org_id        UUID          NOT NULL,
    hotel_id      VARCHAR(100)  NOT NULL,
    city          VARCHAR(100)  NOT NULL,
    checkin_date  DATE          NOT NULL,
    checkout_date DATE          NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    status        VARCHAR(50)   NOT NULL,
    created_at    TIMESTAMP     NOT NULL DEFAULT NOW(),

    -- Enforce checkout must be after checkin
    CONSTRAINT chk_checkout_after_checkin CHECK (checkout_date > checkin_date),

    -- Enforce valid status values
    CONSTRAINT chk_valid_status CHECK (
        status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW')
    )
);

COMMENT ON TABLE  hotel_bookings                IS 'Core bookings table — one row per hotel reservation';
COMMENT ON COLUMN hotel_bookings.id             IS 'Globally unique booking identifier (UUID v4)';
COMMENT ON COLUMN hotel_bookings.org_id         IS 'Organisation that made the booking';
COMMENT ON COLUMN hotel_bookings.hotel_id       IS 'Identifier of the hotel (external reference)';
COMMENT ON COLUMN hotel_bookings.city           IS 'City where the hotel is located';
COMMENT ON COLUMN hotel_bookings.checkin_date   IS 'Booked check-in date';
COMMENT ON COLUMN hotel_bookings.checkout_date  IS 'Booked check-out date';
COMMENT ON COLUMN hotel_bookings.amount         IS 'Total booking amount in the local currency';
COMMENT ON COLUMN hotel_bookings.status         IS 'Lifecycle status of the booking';
COMMENT ON COLUMN hotel_bookings.created_at     IS 'Timestamp when the booking record was created';
