-- =====================================================================
-- Short-Term Rental & Smart Access Management System
-- 02_indexes_views_roles_transactions.sql
-- Indexes, Views, Roles and Permissions, Transactions
-- =====================================================================
USE rental_access_db;

-- =====================================================================
-- PART 1 - INDEXES
-- =====================================================================
-- Note: idx_bookings_property_dates, idx_bookings_guest_status, and
-- idx_events_device_time already exist from the original schema and
-- are retained as-is. Only new indexes are created here.

-- Property search by location and price.
-- Replaces idx_properties_city_active_price with a cleaner version
-- that omits the low-cardinality is_active boolean column.
CREATE INDEX idx_properties_city_price
    ON properties (city_id, base_price_night);

-- Access code window lookups by booking and expiry.
-- Replaces idx_codes_active_window with a more selective version.
CREATE INDEX idx_codes_booking_validity
    ON access_codes (booking_id, valid_until);

-- Cleaner assignment lookups — new column added in schema upgrade.
CREATE INDEX idx_codes_assigned_to
    ON access_codes (assigned_to);

-- Maintenance request status filtering per property.
CREATE INDEX idx_maintenance_property_status
    ON maintenance_requests (property_id, request_status);

-- Message inbox queries per recipient.
CREATE INDEX idx_messages_receiver_read
    ON messages (receiver_id, is_read);


-- =====================================================================
-- PART 2 - VIEWS
-- =====================================================================

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
    p.bathrooms,
    p.base_price_night,
    p.cleaning_fee,
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
         p.bedrooms, p.bathrooms, p.base_price_night, p.cleaning_fee,
         cur.currency_code;

CREATE OR REPLACE VIEW v_upcoming_checkins AS
SELECT
    b.booking_id,
    b.check_in_date,
    b.check_out_date,
    p.title                                 AS property_title,
    CONCAT(u.first_name, ' ', u.last_name)  AS guest_name,
    u.email                                 AS guest_email,
    b.num_guests,
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
WHERE b.check_in_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 14 DAY)
  AND bs.status_name IN ('confirmed', 'pending');

CREATE OR REPLACE VIEW v_host_revenue AS
SELECT
    hp.host_id,
    CONCAT(u.first_name, ' ', u.last_name)  AS host_name,
    hp.is_superhost,
    COUNT(DISTINCT p.property_id)           AS total_properties,
    COUNT(DISTINCT b.booking_id)            AS total_bookings,
    COALESCE(SUM(b.total_amount), 0)        AS gross_revenue,
    COALESCE(SUM(po.net_amount), 0)         AS net_paid_out,
    COALESCE(SUM(b.total_amount), 0)
        - COALESCE(SUM(po.net_amount), 0)   AS pending_payout
FROM host_profiles hp
JOIN users u              ON u.user_id = hp.host_id
LEFT JOIN properties p    ON p.host_id = hp.host_id
LEFT JOIN bookings b      ON b.property_id = p.property_id
LEFT JOIN host_payouts po ON po.booking_id = b.booking_id
                         AND po.payout_status = 'paid'
GROUP BY hp.host_id, u.first_name, u.last_name, hp.is_superhost;

CREATE OR REPLACE VIEW v_access_audit AS
SELECT
    ae.event_id,
    ae.event_time,
    ae.event_type,
    p.title                                         AS property_title,
    sd.location_label,
    sd.serial_number,
    ac.code_value,
    act.type_name                                   AS code_type,
    b.booking_id,
    CONCAT(gu.first_name, ' ', gu.last_name)        AS guest_name,
    CONCAT(cu.first_name, ' ', cu.last_name)        AS assigned_cleaner,
    ae.details
FROM access_events ae
JOIN smart_devices sd           ON sd.device_id = ae.device_id
JOIN properties p               ON p.property_id = sd.property_id
LEFT JOIN access_codes ac       ON ac.code_id = ae.code_id
LEFT JOIN access_code_types act ON act.code_type_id = ac.code_type_id
LEFT JOIN bookings b            ON b.booking_id = ac.booking_id
LEFT JOIN users gu              ON gu.user_id = b.guest_id
LEFT JOIN users cu              ON cu.user_id = ac.assigned_to;

CREATE OR REPLACE VIEW v_unverified_upcoming_guests AS
SELECT DISTINCT
    u.user_id,
    CONCAT(u.first_name, ' ', u.last_name) AS guest_name,
    u.email,
    b.booking_id,
    b.check_in_date,
    DATEDIFF(b.check_in_date, CURDATE())   AS days_until_checkin
FROM bookings b
JOIN users u ON u.user_id = b.guest_id
WHERE b.check_in_date >= CURDATE()
  AND NOT EXISTS (
        SELECT 1 FROM guest_verifications gv
        WHERE gv.guest_id = b.guest_id
          AND gv.status = 'approved'
  )
ORDER BY b.check_in_date ASC;

CREATE OR REPLACE VIEW v_property_performance AS
SELECT
    p.property_id,
    p.title,
    ci.city_name,
    CONCAT(u.first_name, ' ', u.last_name)      AS host_name,
    COUNT(DISTINCT b.booking_id)                AS total_bookings,
    COALESCE(SUM(b.total_amount), 0)            AS total_revenue,
    ROUND(AVG(r.overall_rating), 2)             AS avg_rating,
    COUNT(DISTINCT r.review_id)                 AS review_count,
    COALESCE(SUM(DATEDIFF(
        b.check_out_date, b.check_in_date)), 0) AS total_nights_booked
FROM properties p
JOIN cities ci          ON ci.city_id = p.city_id
JOIN host_profiles hp   ON hp.host_id = p.host_id
JOIN users u            ON u.user_id = hp.host_id
LEFT JOIN bookings b    ON b.property_id = p.property_id
LEFT JOIN reviews r     ON r.booking_id = b.booking_id AND r.is_visible = 1
GROUP BY p.property_id, p.title, ci.city_name, u.first_name, u.last_name;

CREATE OR REPLACE VIEW v_guest_booking_history AS
SELECT
    u.user_id,
    CONCAT(u.first_name, ' ', u.last_name)  AS guest_name,
    b.booking_id,
    p.title                                 AS property_title,
    ci.city_name,
    b.check_in_date,
    b.check_out_date,
    DATEDIFF(b.check_out_date,
        b.check_in_date)                    AS nights,
    b.total_amount,
    bs.status_name                          AS booking_status,
    ps.status_name                          AS payment_status,
    CASE WHEN r.review_id IS NOT NULL
         THEN 'Reviewed' ELSE 'Not reviewed' END AS review_status
FROM bookings b
JOIN users u             ON u.user_id = b.guest_id
JOIN properties p        ON p.property_id = b.property_id
JOIN cities ci           ON ci.city_id = p.city_id
JOIN booking_statuses bs ON bs.status_id = b.status_id
LEFT JOIN payments py    ON py.booking_id = b.booking_id
LEFT JOIN payment_statuses ps ON ps.status_id = py.status_id
LEFT JOIN reviews r      ON r.booking_id = b.booking_id
ORDER BY b.check_in_date DESC;


-- =====================================================================
-- PART 3 - ROLES AND PERMISSIONS
-- =====================================================================

DROP ROLE IF EXISTS 'role_admin', 'role_host', 'role_guest', 'role_cleaner';
DROP USER IF EXISTS 'app_admin'@'localhost';
DROP USER IF EXISTS 'app_host'@'localhost';
DROP USER IF EXISTS 'app_guest'@'localhost';
DROP USER IF EXISTS 'app_cleaner'@'localhost';

CREATE ROLE 'role_admin';
CREATE ROLE 'role_host';
CREATE ROLE 'role_guest';
CREATE ROLE 'role_cleaner';

GRANT ALL PRIVILEGES ON rental_access_db.* TO 'role_admin';

GRANT SELECT, INSERT, UPDATE         ON rental_access_db.properties             TO 'role_host';
GRANT SELECT, INSERT, UPDATE, DELETE ON rental_access_db.property_photos        TO 'role_host';
GRANT SELECT, INSERT, DELETE         ON rental_access_db.property_amenities     TO 'role_host';
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.seasonal_pricing       TO 'role_host';
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.availability_calendar  TO 'role_host';
GRANT SELECT                         ON rental_access_db.bookings               TO 'role_host';
GRANT SELECT                         ON rental_access_db.v_host_revenue         TO 'role_host';
GRANT SELECT                         ON rental_access_db.v_upcoming_checkins    TO 'role_host';
GRANT SELECT                         ON rental_access_db.v_property_performance TO 'role_host';
GRANT SELECT, INSERT                 ON rental_access_db.review_responses       TO 'role_host';
GRANT SELECT, INSERT, UPDATE         ON rental_access_db.access_codes           TO 'role_host';
GRANT SELECT, INSERT                 ON rental_access_db.maintenance_requests   TO 'role_host';

GRANT SELECT          ON rental_access_db.v_property_catalog      TO 'role_guest';
GRANT SELECT          ON rental_access_db.v_guest_booking_history TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.bookings                TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.booking_guests          TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.reviews                 TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.review_scores           TO 'role_guest';
GRANT SELECT, INSERT  ON rental_access_db.messages                TO 'role_guest';
GRANT SELECT          ON rental_access_db.access_codes            TO 'role_guest';

GRANT SELECT, UPDATE  ON rental_access_db.cleaning_tasks          TO 'role_cleaner';
GRANT SELECT          ON rental_access_db.v_upcoming_checkins     TO 'role_cleaner';
GRANT SELECT          ON rental_access_db.access_codes            TO 'role_cleaner';

CREATE USER 'app_admin'@'localhost'   IDENTIFIED BY 'Admin#2026!';
CREATE USER 'app_host'@'localhost'    IDENTIFIED BY 'Host#2026!';
CREATE USER 'app_guest'@'localhost'   IDENTIFIED BY 'Guest#2026!';
CREATE USER 'app_cleaner'@'localhost' IDENTIFIED BY 'Clean#2026!';

GRANT 'role_admin'   TO 'app_admin'@'localhost';
GRANT 'role_host'    TO 'app_host'@'localhost';
GRANT 'role_guest'   TO 'app_guest'@'localhost';
GRANT 'role_cleaner' TO 'app_cleaner'@'localhost';

SET DEFAULT ROLE 'role_admin'   TO 'app_admin'@'localhost';
SET DEFAULT ROLE 'role_host'    TO 'app_host'@'localhost';
SET DEFAULT ROLE 'role_guest'   TO 'app_guest'@'localhost';
SET DEFAULT ROLE 'role_cleaner' TO 'app_cleaner'@'localhost';

FLUSH PRIVILEGES;


-- =====================================================================
-- PART 4 - STORED PROCEDURES WITH TRANSACTIONS
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_create_booking;
DROP PROCEDURE IF EXISTS sp_confirm_booking;
DROP PROCEDURE IF EXISTS sp_cancel_booking;
DROP PROCEDURE IF EXISTS sp_complete_stay;
DROP PROCEDURE IF EXISTS sp_assign_cleaner_code;

DELIMITER $$

CREATE PROCEDURE sp_create_booking(
    IN  p_property_id      INT,
    IN  p_guest_id         INT,
    IN  p_check_in         DATE,
    IN  p_check_out        DATE,
    IN  p_num_guests       INT,
    IN  p_nightly_rate     DECIMAL(10,2),
    IN  p_total_amount     DECIMAL(10,2),
    IN  p_special_requests TEXT,
    OUT p_booking_id       INT,
    OUT p_message          VARCHAR(255)
)
BEGIN
    DECLARE v_overlap    INT DEFAULT 0;
    DECLARE v_booking_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message    = 'ERROR: unexpected failure - transaction rolled back';
        SET p_booking_id = NULL;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_overlap
    FROM bookings b
    JOIN booking_statuses bs ON bs.status_id = b.status_id
    WHERE b.property_id    = p_property_id
      AND bs.status_name   IN ('confirmed', 'checked_in')
      AND b.check_in_date  < p_check_out
      AND b.check_out_date > p_check_in;

    IF v_overlap > 0 THEN
        ROLLBACK;
        SET p_booking_id = NULL;
        SET p_message    = 'ERROR: property already booked for the requested dates';
    ELSE
        INSERT INTO bookings (
            property_id, guest_id, status_id, currency_id,
            check_in_date, check_out_date, num_guests,
            nightly_rate, total_amount, special_requests
        ) VALUES (
            p_property_id, p_guest_id,
            (SELECT status_id FROM booking_statuses WHERE status_name = 'pending'),
            1, p_check_in, p_check_out, p_num_guests,
            p_nightly_rate, p_total_amount, p_special_requests
        );

        SET v_booking_id = LAST_INSERT_ID();
        SAVEPOINT sp_booking_inserted;

        INSERT INTO booking_guests (booking_id, full_name, date_of_birth, is_primary)
        SELECT v_booking_id, CONCAT(first_name, ' ', last_name), NULL, 1
        FROM users WHERE user_id = p_guest_id;

        SAVEPOINT sp_guest_registered;

        INSERT INTO booking_fees (booking_id, fee_type_id, amount)
        SELECT v_booking_id, fee_type_id,
               CASE WHEN is_percentage = 0 THEN default_amount
                    ELSE ROUND(p_total_amount * default_amount / 100, 2) END
        FROM fee_types
        WHERE fee_name IN ('Cleaning fee', 'Service fee');

        SAVEPOINT sp_fees_recorded;

        UPDATE availability_calendar
        SET is_available = 0
        WHERE property_id  = p_property_id
          AND calendar_date BETWEEN p_check_in
                                AND DATE_SUB(p_check_out, INTERVAL 1 DAY);

        COMMIT;
        SET p_booking_id = v_booking_id;
        SET p_message    = 'SUCCESS: booking created';
    END IF;
END$$


CREATE PROCEDURE sp_confirm_booking(
    IN  p_booking_id  INT,
    IN  p_device_id   INT,
    IN  p_code_value  VARCHAR(40),
    OUT p_message     VARCHAR(255)
)
BEGIN
    DECLARE v_status   VARCHAR(50);
    DECLARE v_checkin  DATE;
    DECLARE v_checkout DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'ERROR: unexpected failure - transaction rolled back';
    END;

    START TRANSACTION;

    SELECT bs.status_name, b.check_in_date, b.check_out_date
    INTO   v_status, v_checkin, v_checkout
    FROM bookings b
    JOIN booking_statuses bs ON bs.status_id = b.status_id
    WHERE b.booking_id = p_booking_id;

    IF v_status != 'pending' THEN
        ROLLBACK;
        SET p_message = CONCAT('ERROR: booking is not pending - current status: ', v_status);
    ELSE
        UPDATE bookings
        SET status_id = (SELECT status_id FROM booking_statuses WHERE status_name = 'confirmed')
        WHERE booking_id = p_booking_id;

        SAVEPOINT sp_status_updated;

        INSERT INTO access_codes (
            device_id, booking_id, code_type_id,
            code_value, valid_from, valid_until, is_active
        ) VALUES (
            p_device_id, p_booking_id,
            (SELECT code_type_id FROM access_code_types WHERE type_name = 'Guest stay code'),
            p_code_value,
            TIMESTAMP(v_checkin,  '15:00:00'),
            TIMESTAMP(v_checkout, '11:00:00'),
            1
        );

        COMMIT;
        SET p_message = 'SUCCESS: booking confirmed and access code issued';
    END IF;
END$$


CREATE PROCEDURE sp_cancel_booking(
    IN  p_booking_id    INT,
    IN  p_payment_id    INT,
    IN  p_refund_amount DECIMAL(10,2),
    IN  p_refund_reason VARCHAR(255),
    OUT p_message       VARCHAR(255)
)
BEGIN
    DECLARE v_status      VARCHAR(50);
    DECLARE v_property_id INT;
    DECLARE v_checkin     DATE;
    DECLARE v_checkout    DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'ERROR: unexpected failure - transaction rolled back';
    END;

    START TRANSACTION;

    SELECT bs.status_name, b.property_id, b.check_in_date, b.check_out_date
    INTO   v_status, v_property_id, v_checkin, v_checkout
    FROM bookings b
    JOIN booking_statuses bs ON bs.status_id = b.status_id
    WHERE b.booking_id = p_booking_id;

    IF v_status NOT IN ('confirmed', 'pending') THEN
        ROLLBACK;
        SET p_message = CONCAT('ERROR: booking cannot be cancelled - current status: ', v_status);
    ELSE
        UPDATE bookings
        SET status_id = (SELECT status_id FROM booking_statuses WHERE status_name = 'cancelled')
        WHERE booking_id = p_booking_id;

        SAVEPOINT sp_cancelled;

        UPDATE access_codes
        SET is_active = 0
        WHERE booking_id = p_booking_id;

        SAVEPOINT sp_codes_deactivated;

        INSERT INTO refunds (payment_id, amount, reason)
        VALUES (p_payment_id, p_refund_amount, p_refund_reason);

        SAVEPOINT sp_refund_recorded;

        UPDATE availability_calendar
        SET is_available = 1
        WHERE property_id  = v_property_id
          AND calendar_date BETWEEN v_checkin
                                AND DATE_SUB(v_checkout, INTERVAL 1 DAY);

        COMMIT;
        SET p_message = 'SUCCESS: booking cancelled, codes deactivated, refund recorded';
    END IF;
END$$


CREATE PROCEDURE sp_complete_stay(
    IN  p_booking_id INT,
    IN  p_host_id    INT,
    OUT p_message    VARCHAR(255)
)
BEGIN
    DECLARE v_status VARCHAR(50);
    DECLARE v_gross  DECIMAL(10,2);
    DECLARE v_fee    DECIMAL(10,2);
    DECLARE v_net    DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'ERROR: unexpected failure - transaction rolled back';
    END;

    START TRANSACTION;

    SELECT bs.status_name, b.total_amount
    INTO   v_status, v_gross
    FROM bookings b
    JOIN booking_statuses bs ON bs.status_id = b.status_id
    WHERE b.booking_id = p_booking_id;

    IF v_status != 'checked_in' THEN
        ROLLBACK;
        SET p_message = CONCAT('ERROR: booking must be checked_in - current status: ', v_status);
    ELSE
        UPDATE bookings
        SET status_id = (SELECT status_id FROM booking_statuses WHERE status_name = 'completed')
        WHERE booking_id = p_booking_id;

        SAVEPOINT sp_completed;

        SET v_fee = ROUND(v_gross * 0.12, 2);
        SET v_net = ROUND(v_gross - v_fee, 2);

        INSERT INTO host_payouts (
            host_id, booking_id,
            gross_amount, platform_fee, net_amount,
            payout_status, payout_date
        ) VALUES (
            p_host_id, p_booking_id,
            v_gross, v_fee, v_net,
            'pending', NULL
        );

        COMMIT;
        SET p_message = CONCAT('SUCCESS: stay completed - payout of ', v_net, ' EUR queued for host');
    END IF;
END$$


CREATE PROCEDURE sp_assign_cleaner_code(
    IN  p_code_id     INT,
    IN  p_cleaner_id  INT,
    IN  p_valid_from  DATETIME,
    IN  p_valid_until DATETIME,
    OUT p_message     VARCHAR(255)
)
BEGIN
    DECLARE v_assignee INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_message = 'ERROR: unexpected failure - transaction rolled back';
    END;

    START TRANSACTION;

    SELECT assigned_to INTO v_assignee
    FROM access_codes
    WHERE code_id = p_code_id;

    IF v_assignee IS NOT NULL THEN
        ROLLBACK;
        SET p_message = 'ERROR: access code is already assigned to another cleaner';
    ELSE
        UPDATE access_codes
        SET assigned_to = p_cleaner_id,
            is_active   = 1,
            valid_from  = p_valid_from,
            valid_until = p_valid_until
        WHERE code_id = p_code_id;

        COMMIT;
        SET p_message = 'SUCCESS: cleaner assigned and code activated';
    END IF;
END$$

DELIMITER ;


