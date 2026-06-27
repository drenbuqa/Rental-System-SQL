-- =====================================================================
-- Short-Term Rental & Smart Access Management System
-- 02_indexes_views_security_transactions.sql
-- Indexes, Views, Roles and Permission, Transactions
-- =====================================================================
USE rental_access_db;

-- =====================================================================
-- PART 1 — INDEXES
-- =====================================================================

-- Availability search: the most frequent query in the system.
-- Optimizes the NOT EXISTS overlap check in search_available and
-- the pre-insert validation inside create_booking in the Python app.
CREATE INDEX idx_bookings_property_dates
    ON bookings (property_id, check_in_date, check_out_date);

-- Guest booking history and status filtering.
-- Optimizes status filtering in upcoming_checkins in the Python app
-- and the v_upcoming_checkins view. guest_id leads the index and has
-- high cardinality; status_id filters within the small result set.
CREATE INDEX idx_bookings_guest_status
    ON bookings (guest_id, status_id);

-- Property search by location, active status, and price.
-- Optimizes the is_active = 1 filter in v_property_catalog and
-- the search_available function in the Python app. city_id leads
-- with high cardinality; is_active and base_price_night narrow further.
CREATE INDEX idx_properties_city_active_price
    ON properties (city_id, is_active, base_price_night);

-- Access code validity checks and expired code cleanup.
-- Optimizes purge_expired_codes DELETE in the Python app (is_active=0,
-- valid_until < NOW()) and the active code COUNT correlated subquery
-- inside upcoming_checkins (is_active=1).
CREATE INDEX idx_codes_active_window
    ON access_codes (is_active, valid_from, valid_until);

-- =====================================================================
-- PART 2 — VIEWS
-- =====================================================================

-- View 1: Public catalog — property with host, location, type and
-- aggregated review statistics. Hides internal columns (IBAN, tax no.).
-- LEFT JOIN to bookings and reviews so new properties with no bookings
-- or reviews still appear in the catalog.
CREATE OR REPLACE VIEW v_property_catalog AS
SELECT
    p.property_id,
    p.title,
    pt.type_name                            AS property_type,
    ci.city_name,
    co.country_name,
    CONCAT(u.first_name, ' ', u.last_name)  AS host_name,
    hp.is_superhost,
    p.max_guests,
    p.bedrooms,
    p.base_price_night,
    cur.currency_code,
    COUNT(r.review_id)                      AS review_count,
    ROUND(AVG(r.overall_rating), 2)         AS avg_rating
FROM properties p
JOIN property_types pt  ON pt.property_type_id = p.property_type_id
JOIN cities ci          ON ci.city_id = p.city_id
JOIN countries co       ON co.country_id = ci.country_id
JOIN host_profiles hp   ON hp.host_id = p.host_id
JOIN users u            ON u.user_id = hp.host_id
JOIN currencies cur     ON cur.currency_id = p.currency_id
LEFT JOIN bookings b    ON b.property_id = p.property_id
LEFT JOIN reviews r     ON r.booking_id = b.booking_id AND r.is_visible = 1
WHERE p.is_active = 1
GROUP BY p.property_id, p.title, pt.type_name, ci.city_name, co.country_name,
         u.first_name, u.last_name, hp.is_superhost, p.max_guests,
         p.bedrooms, p.base_price_night, cur.currency_code;

-- View 2: Operations dashboard — upcoming check-ins in the next 7 days.
-- Two correlated subqueries per row: one finds the most recent
-- verification status for the guest, one counts active door codes.
-- Used by operations staff every morning to confirm guests are ready.
CREATE OR REPLACE VIEW v_upcoming_checkins AS
SELECT
    b.booking_id,
    b.check_in_date,
    p.title                                 AS property_title,
    CONCAT(u.first_name, ' ', u.last_name)  AS guest_name,
    bs.status_name                          AS booking_status,
    (SELECT gv.status
       FROM guest_verifications gv
      WHERE gv.guest_id = b.guest_id
      ORDER BY gv.submitted_at DESC
      LIMIT 1)                              AS verification_status,
    (SELECT COUNT(*)
       FROM access_codes ac
      WHERE ac.booking_id = b.booking_id
        AND ac.is_active = 1)               AS active_codes
FROM bookings b
JOIN properties p        ON p.property_id = b.property_id
JOIN users u             ON u.user_id = b.guest_id
JOIN booking_statuses bs ON bs.status_id = b.status_id
WHERE b.check_in_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY)
  AND bs.status_name IN ('confirmed','pending');

-- View 3: Host revenue summary — financial reporting per host.
-- COALESCE replaces NULL with 0 so hosts with no bookings show 0
-- rather than NULL in financial columns.
-- LEFT JOIN host_payouts with AND payout_status='paid' so only
-- completed payouts are summed, not pending ones.
CREATE OR REPLACE VIEW v_host_revenue AS
SELECT
    hp.host_id,
    CONCAT(u.first_name, ' ', u.last_name)  AS host_name,
    COUNT(DISTINCT b.booking_id)            AS total_bookings,
    COALESCE(SUM(b.total_amount), 0)        AS gross_revenue,
    COALESCE(SUM(po.net_amount), 0)         AS net_paid_out
FROM host_profiles hp
JOIN users u            ON u.user_id = hp.host_id
LEFT JOIN properties p  ON p.host_id = hp.host_id
LEFT JOIN bookings b    ON b.property_id = p.property_id
LEFT JOIN host_payouts po ON po.booking_id = b.booking_id
                         AND po.payout_status = 'paid'
GROUP BY hp.host_id, u.first_name, u.last_name;

-- View 4: Security audit — every lock event with full context.
-- Multiple LEFT JOINs preserve events that have no associated code or
-- guest — battery alerts and tamper alerts have no code, so a regular
-- JOIN would drop those rows from the audit log entirely.
CREATE OR REPLACE VIEW v_access_audit AS
SELECT
    ae.event_id,
    ae.event_time,
    ae.event_type,
    p.title             AS property_title,
    sd.location_label,
    sd.serial_number,
    ac.code_value,
    b.booking_id,
    CONCAT(u.first_name, ' ', u.last_name) AS guest_name
FROM access_events ae
JOIN smart_devices sd       ON sd.device_id = ae.device_id
JOIN properties p           ON p.property_id = sd.property_id
LEFT JOIN access_codes ac   ON ac.code_id = ae.code_id
LEFT JOIN bookings b        ON b.booking_id = ac.booking_id
LEFT JOIN users u           ON u.user_id = b.guest_id;

-- View 5: Compliance — guests with upcoming stays who are not yet
-- verified. NOT EXISTS subquery returns true when no approved
-- verification exists for the guest. Drives reminder emails.
CREATE OR REPLACE VIEW v_unverified_upcoming_guests AS
SELECT DISTINCT
    u.user_id,
    CONCAT(u.first_name, ' ', u.last_name) AS guest_name,
    u.email,
    b.booking_id,
    b.check_in_date
FROM bookings b
JOIN users u ON u.user_id = b.guest_id
WHERE b.check_in_date >= CURDATE()
  AND NOT EXISTS (
        SELECT 1 FROM guest_verifications gv
        WHERE gv.guest_id = b.guest_id AND gv.status = 'approved'
  );

-- =====================================================================
-- PART 3 — ROLES AND PERMISSIONS
-- =====================================================================

DROP ROLE IF EXISTS 'role_admin', 'role_host', 'role_guest', 'role_cleaner';
DROP USER IF EXISTS 'app_admin'@'localhost';
DROP USER IF EXISTS 'app_host'@'localhost';
DROP USER IF EXISTS 'app_guest'@'localhost';
DROP USER IF EXISTS 'app_cleaner'@'localhost';

-- Step 1: define roles
CREATE ROLE 'role_admin';
CREATE ROLE 'role_host';
CREATE ROLE 'role_guest';
CREATE ROLE 'role_cleaner';

-- Step 2: grant privileges to roles

-- role_admin: full access to the application schema
GRANT ALL PRIVILEGES ON rental_access_db.* TO 'role_admin';

-- role_host: manage own listings, pricing, access codes; read bookings
-- No DELETE on properties — prevents destroying listing history
-- No INSERT on bookings — hosts cannot fabricate reservations
-- SELECT on bookings only — not on payments or guest personal data
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.properties            TO 'role_host';
GRANT SELECT, INSERT, UPDATE, DELETE ON rental_access_db.property_photos       TO 'role_host';
GRANT SELECT, INSERT, DELETE         ON rental_access_db.property_amenities    TO 'role_host';
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.seasonal_pricing      TO 'role_host';
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.availability_calendar TO 'role_host';
GRANT SELECT                         ON rental_access_db.bookings              TO 'role_host';
GRANT SELECT                         ON rental_access_db.v_host_revenue        TO 'role_host';
GRANT SELECT                         ON rental_access_db.v_upcoming_checkins   TO 'role_host';
GRANT SELECT, INSERT                 ON rental_access_db.review_responses      TO 'role_host';
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.access_codes          TO 'role_host';

-- role_guest: read the public catalog, write own bookings and reviews
-- SELECT on v_property_catalog (not raw properties) — hides host IBAN,
-- coordinates, and internal columns from public view
GRANT SELECT          ON rental_access_db.v_property_catalog TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.bookings           TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.booking_guests     TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.reviews            TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.review_scores      TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.messages           TO 'role_guest';

-- role_cleaner: cleaning roster and check-in schedule only
-- No access to payments, guest data, or any financial information
GRANT SELECT, UPDATE                 ON rental_access_db.cleaning_tasks        TO 'role_cleaner';
GRANT SELECT                         ON rental_access_db.v_upcoming_checkins   TO 'role_cleaner';

-- Step 3: create login accounts
CREATE USER 'app_admin'@'localhost'   IDENTIFIED BY 'Admin#2026!';
CREATE USER 'app_host'@'localhost'    IDENTIFIED BY 'Host#2026!';
CREATE USER 'app_guest'@'localhost'   IDENTIFIED BY 'Guest#2026!';
CREATE USER 'app_cleaner'@'localhost' IDENTIFIED BY 'Clean#2026!';

-- Step 4: assign roles to users
GRANT 'role_admin'   TO 'app_admin'@'localhost';
GRANT 'role_host'    TO 'app_host'@'localhost';
GRANT 'role_guest'   TO 'app_guest'@'localhost';
GRANT 'role_cleaner' TO 'app_cleaner'@'localhost';

-- Step 5: activate roles automatically on login
-- Without this the role is inactive until the user manually runs
-- SET ROLE, which breaks application connections silently
SET DEFAULT ROLE 'role_admin'   TO 'app_admin'@'localhost';
SET DEFAULT ROLE 'role_host'    TO 'app_host'@'localhost';
SET DEFAULT ROLE 'role_guest'   TO 'app_guest'@'localhost';
SET DEFAULT ROLE 'role_cleaner' TO 'app_cleaner'@'localhost';

FLUSH PRIVILEGES;

-- =====================================================================
-- PART 4 — TRANSACTIONS
-- =====================================================================

-- TRANSACTION 1: Create a New Booking
-- Business event: Guest (Mia Holz, guest_id=7) books the Vienna Penthouse (property_id=2) for 4 nights.
START TRANSACTION;

    INSERT INTO bookings (
        property_id, guest_id, status_id, currency_id,
        check_in_date, check_out_date, num_guests,
        nightly_rate, total_amount, special_requests
    ) VALUES (
        2, 7, 1, 1,
        '2026-08-01', '2026-08-05', 2,
        320.00, 1410.00, 'High floor preferred if possible'
    );

    -- Save the new booking_id before any further inserts overwrite it.
    -- LAST_INSERT_ID() would be overwritten by the next INSERT, so it
    -- must be captured into a variable immediately after the booking INSERT.
    SET @new_booking_id = LAST_INSERT_ID();

    -- Register the primary traveler
    INSERT INTO booking_guests (booking_id, full_name, date_of_birth, is_primary)
    VALUES (@new_booking_id, 'Mia Holz', '2000-06-18', 1);

    -- Record the fees applicable to this booking
    INSERT INTO booking_fees (booking_id, fee_type_id, amount)
    VALUES
        (@new_booking_id, 1, 80.00),   -- Cleaning fee (fee_type_id=1)
        (@new_booking_id, 2, 50.00);   -- Service fee  (fee_type_id=2)

    -- Block the stay dates in the availability calendar
    UPDATE availability_calendar
    SET is_available = 0
    WHERE property_id = 2
      AND calendar_date BETWEEN '2026-08-01' AND '2026-08-04';

COMMIT;


-- TRANSACTION 2: Confirm Booking and Generate Access Code
-- The system confirms booking_id=4 (Mia + Berlin house) and issues a door code to the guest.

START TRANSACTION;

    UPDATE bookings
    SET status_id = 2
    WHERE booking_id = 4;

    -- Issue the access code tied to the Berlin front-door lock (device_id=5)
    INSERT INTO access_codes (
        device_id, booking_id, code_type_id,
        code_value, valid_from, valid_until, is_active
    ) VALUES (
        5, 4, 1,
        '334455',
        '2026-07-01 15:00:00',
        '2026-07-08 11:00:00',
        1
    );

COMMIT;


-- TRANSACTION 3: Cancel Booking and Process Refund
-- Booking_id=4 is cancelled. Under the Moderate policy the guest receives a 50% refund.

START TRANSACTION;

    UPDATE bookings
    SET status_id = 5
    WHERE booking_id = 4;

    -- Deactivate the code so the cancelled guest can no longer enter
    UPDATE access_codes
    SET is_active = 0
    WHERE booking_id = 4;

    -- Record the 50% refund against the original payment (payment_id=4)
    INSERT INTO refunds (payment_id, amount, reason)
    VALUES (
        4,
        765.00,
        'Guest cancellation under Moderate policy — 50% refund applied'
    );

    -- Free the dates so other guests can now book them
    UPDATE availability_calendar
    SET is_available = 1
    WHERE property_id = 4
      AND calendar_date BETWEEN '2026-07-01' AND '2026-07-07';

COMMIT;


-- TRANSACTION 4: Complete Stay and Process Host Payout
-- The booking created in Transaction 1 (Mia at the Vienna Penthouse) has checked out. 
-- The stay is marked complete and the host payout is created. Platform fee is 12% of gross.

START TRANSACTION;

    UPDATE bookings
    SET status_id = 4
    WHERE booking_id = @new_booking_id;

    -- 12% platform fee on 1410.00 gross = 169.20 fee, 1240.80 net
    INSERT INTO host_payouts (
        host_id, booking_id,
        gross_amount, platform_fee, net_amount,
        payout_status, payout_date
    ) VALUES (
        1, @new_booking_id,
        1410.00, 169.20, 1240.80,
        'pending', NULL
    );

COMMIT;