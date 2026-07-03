-- =====================================================================
-- Short-Term Rental & Smart Access Management System
-- 01_schema.sql — Database + 46 tables (17 reference, 29 transactional)
-- =====================================================================

DROP DATABASE IF EXISTS rental_access_db;
CREATE DATABASE rental_access_db;
USE rental_access_db;

-- =====================================================================
-- SECTION A — REFERENCE TABLES [17 tables]
-- Reference tables hold stable classification data that rarely changes.
-- =====================================================================

-- 1. countries
CREATE TABLE countries (
    country_id      INT AUTO_INCREMENT PRIMARY KEY,
    country_name    VARCHAR(80)  NOT NULL,
    iso_code        CHAR(2)      NOT NULL,
    UNIQUE KEY uq_countries_name (country_name),
    UNIQUE KEY uq_countries_iso  (iso_code)
);

-- 2. cities
CREATE TABLE cities (
    city_id         INT AUTO_INCREMENT PRIMARY KEY,
    country_id      INT          NOT NULL,
    city_name       VARCHAR(80)  NOT NULL,
    postal_region   VARCHAR(20)  NULL,
    UNIQUE KEY uq_cities_country_name (country_id, city_name),
    CONSTRAINT fk_cities_country FOREIGN KEY (country_id)
        REFERENCES countries (country_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 3. currencies
CREATE TABLE currencies (
    currency_id     INT AUTO_INCREMENT PRIMARY KEY,
    currency_code   CHAR(3)      NOT NULL,
    currency_name   VARCHAR(50)  NOT NULL,
    UNIQUE KEY uq_currencies_code (currency_code)
);

-- 4. languages
CREATE TABLE languages (
    language_id     INT AUTO_INCREMENT PRIMARY KEY,
    language_code   CHAR(2)      NOT NULL,
    language_name   VARCHAR(50)  NOT NULL,
    UNIQUE KEY uq_languages_code (language_code)
);

-- 5. property_types
CREATE TABLE property_types (
    property_type_id INT AUTO_INCREMENT PRIMARY KEY,
    type_name        VARCHAR(50)  NOT NULL,
    description      VARCHAR(255) NULL,
    UNIQUE KEY uq_property_types_name (type_name)
);

-- 6. room_types
CREATE TABLE room_types (
    room_type_id    INT AUTO_INCREMENT PRIMARY KEY,
    type_name       VARCHAR(50)  NOT NULL,
    UNIQUE KEY uq_room_types_name (type_name)
);

-- 7. amenities
CREATE TABLE amenities (
    amenity_id      INT AUTO_INCREMENT PRIMARY KEY,
    amenity_name    VARCHAR(60)  NOT NULL,
    category        VARCHAR(40)  NULL,
    UNIQUE KEY uq_amenities_name (amenity_name)
);

-- 8. cancellation_policies
-- free_cancel_days: TINYINT is sufficient — no policy exceeds 127 days
CREATE TABLE cancellation_policies (
    policy_id        INT AUTO_INCREMENT PRIMARY KEY,
    policy_name      VARCHAR(50)  NOT NULL,
    free_cancel_days TINYINT      NOT NULL DEFAULT 0,
    refund_percent   DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    description      VARCHAR(255) NULL,
    UNIQUE KEY uq_cancellation_policies_name (policy_name)
);

-- 9. booking_statuses
CREATE TABLE booking_statuses (
    status_id       INT AUTO_INCREMENT PRIMARY KEY,
    status_name     VARCHAR(30)  NOT NULL,
    UNIQUE KEY uq_booking_statuses_name (status_name)
);

-- 10. payment_methods
CREATE TABLE payment_methods (
    method_id       INT AUTO_INCREMENT PRIMARY KEY,
    method_name     VARCHAR(40)  NOT NULL,
    UNIQUE KEY uq_payment_methods_name (method_name)
);

-- 11. payment_statuses
CREATE TABLE payment_statuses (
    status_id       INT AUTO_INCREMENT PRIMARY KEY,
    status_name     VARCHAR(30)  NOT NULL,
    UNIQUE KEY uq_payment_statuses_name (status_name)
);

-- 12. fee_types
CREATE TABLE fee_types (
    fee_type_id     INT AUTO_INCREMENT PRIMARY KEY,
    fee_name        VARCHAR(50)  NOT NULL,
    is_percentage   TINYINT(1)   NOT NULL DEFAULT 0,
    default_amount  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    UNIQUE KEY uq_fee_types_name (fee_name)
);

-- 13. id_document_types
CREATE TABLE id_document_types (
    doc_type_id     INT AUTO_INCREMENT PRIMARY KEY,
    type_name       VARCHAR(50)  NOT NULL,
    UNIQUE KEY uq_id_document_types_name (type_name)
);

-- 14. device_types
CREATE TABLE device_types (
    device_type_id  INT AUTO_INCREMENT PRIMARY KEY,
    type_name       VARCHAR(50)  NOT NULL,
    manufacturer    VARCHAR(60)  NULL,
    UNIQUE KEY uq_device_types_name (type_name)
);

-- 15. access_code_types
CREATE TABLE access_code_types (
    code_type_id    INT AUTO_INCREMENT PRIMARY KEY,
    type_name       VARCHAR(40)  NOT NULL,
    max_uses        INT          NULL,
    UNIQUE KEY uq_access_code_types_name (type_name)
);

-- 16. review_categories
-- VARCHAR(50) matches maintenance_categories for consistency
CREATE TABLE review_categories (
    category_id     INT AUTO_INCREMENT PRIMARY KEY,
    category_name   VARCHAR(50)  NOT NULL,
    UNIQUE KEY uq_review_categories_name (category_name)
);

-- 17. maintenance_categories
CREATE TABLE maintenance_categories (
    category_id     INT AUTO_INCREMENT PRIMARY KEY,
    category_name   VARCHAR(50)  NOT NULL,
    priority_level  TINYINT      NOT NULL DEFAULT 3,
    UNIQUE KEY uq_maintenance_categories_name (category_name)
);

-- =====================================================================
-- SECTION B — TRANSACTIONAL TABLES [29 tables]
-- Transactional tables record business events and operational data.
-- =====================================================================

-- 18. users
-- email: VARCHAR(255) per RFC 5321 maximum email length standard
CREATE TABLE users (
    user_id               INT AUTO_INCREMENT PRIMARY KEY,
    email                 VARCHAR(255) NOT NULL,
    password_hash         VARCHAR(255) NOT NULL,
    first_name            VARCHAR(60)  NOT NULL,
    last_name             VARCHAR(60)  NOT NULL,
    phone                 VARCHAR(30)  NULL,
    preferred_language_id INT          NULL,
    account_role          ENUM('guest','host','admin','staff') NOT NULL DEFAULT 'guest',
    is_active             TINYINT(1)   NOT NULL DEFAULT 1,
    created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_users_email (email),
    CONSTRAINT fk_users_language FOREIGN KEY (preferred_language_id)
        REFERENCES languages (language_id) ON UPDATE CASCADE ON DELETE SET NULL
);

-- 19. host_profiles (1:1 extension of users — host_id is both PK and FK)
CREATE TABLE host_profiles (
    host_id         INT PRIMARY KEY,
    company_name    VARCHAR(120) NULL,
    tax_number      VARCHAR(40)  NULL,
    payout_iban     VARCHAR(34)  NULL,
    is_superhost    TINYINT(1)   NOT NULL DEFAULT 0,
    joined_date     DATE         NOT NULL,
    CONSTRAINT fk_host_profiles_user FOREIGN KEY (host_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 20. guest_profiles (1:1 extension of users)
CREATE TABLE guest_profiles (
    guest_id               INT PRIMARY KEY,
    date_of_birth          DATE NULL,
    nationality_country_id INT  NULL,
    emergency_contact      VARCHAR(120) NULL,
    CONSTRAINT fk_guest_profiles_user FOREIGN KEY (guest_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_guest_profiles_country FOREIGN KEY (nationality_country_id)
        REFERENCES countries (country_id) ON UPDATE CASCADE ON DELETE SET NULL
);

-- 21. properties
CREATE TABLE properties (
    property_id            INT AUTO_INCREMENT PRIMARY KEY,
    host_id                INT          NOT NULL,
    property_type_id       INT          NOT NULL,
    city_id                INT          NOT NULL,
    currency_id            INT          NOT NULL,
    cancellation_policy_id INT          NOT NULL,
    title                  VARCHAR(150) NOT NULL,
    description            TEXT         NULL,
    street_address         VARCHAR(150) NOT NULL,
    latitude               DECIMAL(9,6) NULL,
    longitude              DECIMAL(9,6) NULL,
    max_guests             TINYINT      NOT NULL DEFAULT 2,
    bedrooms               TINYINT      NOT NULL DEFAULT 1,
    bathrooms              TINYINT      NOT NULL DEFAULT 1,
    base_price_night       DECIMAL(10,2) NOT NULL,
    cleaning_fee           DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    is_active              TINYINT(1)   NOT NULL DEFAULT 1,
    created_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_properties_host FOREIGN KEY (host_id)
        REFERENCES host_profiles (host_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_properties_type FOREIGN KEY (property_type_id)
        REFERENCES property_types (property_type_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_properties_city FOREIGN KEY (city_id)
        REFERENCES cities (city_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_properties_currency FOREIGN KEY (currency_id)
        REFERENCES currencies (currency_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_properties_policy FOREIGN KEY (cancellation_policy_id)
        REFERENCES cancellation_policies (policy_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 22. property_photos
CREATE TABLE property_photos (
    photo_id        INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    file_url        VARCHAR(255) NOT NULL,
    caption         VARCHAR(150) NULL,
    sort_order      TINYINT      NOT NULL DEFAULT 1,
    is_cover        TINYINT(1)   NOT NULL DEFAULT 0,
    CONSTRAINT fk_property_photos_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 23. property_amenities (M:N bridge table — composite primary key)
CREATE TABLE property_amenities (
    property_id     INT NOT NULL,
    amenity_id      INT NOT NULL,
    PRIMARY KEY (property_id, amenity_id),
    CONSTRAINT fk_pa_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_pa_amenity FOREIGN KEY (amenity_id)
        REFERENCES amenities (amenity_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 24. property_rooms
CREATE TABLE property_rooms (
    room_id         INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    room_type_id    INT          NOT NULL,
    room_name       VARCHAR(60)  NOT NULL,
    size_sqm        DECIMAL(6,2) NULL,
    max_occupancy   TINYINT      NOT NULL DEFAULT 2,
    CONSTRAINT fk_rooms_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_rooms_type FOREIGN KEY (room_type_id)
        REFERENCES room_types (room_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 25. seasonal_pricing
CREATE TABLE seasonal_pricing (
    season_id       INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    season_name     VARCHAR(60)  NOT NULL,
    start_date      DATE         NOT NULL,
    end_date        DATE         NOT NULL,
    nightly_price   DECIMAL(10,2) NOT NULL,
    min_nights      TINYINT      NOT NULL DEFAULT 1,
    CONSTRAINT fk_seasonal_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 26. availability_calendar
CREATE TABLE availability_calendar (
    calendar_id     INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    calendar_date   DATE         NOT NULL,
    is_available    TINYINT(1)   NOT NULL DEFAULT 1,
    price_override  DECIMAL(10,2) NULL,
    UNIQUE KEY uq_calendar_property_date (property_id, calendar_date),
    CONSTRAINT fk_calendar_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 27. bookings
-- special_requests: TEXT instead of VARCHAR(500) — no predictable length limit
CREATE TABLE bookings (
    booking_id      INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    guest_id        INT          NOT NULL,
    status_id       INT          NOT NULL,
    currency_id     INT          NOT NULL,
    check_in_date   DATE         NOT NULL,
    check_out_date  DATE         NOT NULL,
    num_guests      TINYINT      NOT NULL DEFAULT 1,
    nightly_rate    DECIMAL(10,2) NOT NULL,
    total_amount    DECIMAL(10,2) NOT NULL,
    special_requests TEXT         NULL,
    booked_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_bookings_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_guest FOREIGN KEY (guest_id)
        REFERENCES guest_profiles (guest_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_status FOREIGN KEY (status_id)
        REFERENCES booking_statuses (status_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_bookings_currency FOREIGN KEY (currency_id)
        REFERENCES currencies (currency_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 28. booking_guests
CREATE TABLE booking_guests (
    booking_guest_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id       INT          NOT NULL,
    full_name        VARCHAR(120) NOT NULL,
    date_of_birth    DATE         NULL,
    is_primary       TINYINT(1)   NOT NULL DEFAULT 0,
    CONSTRAINT fk_booking_guests_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 29. booking_fees
CREATE TABLE booking_fees (
    booking_fee_id  INT AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT          NOT NULL,
    fee_type_id     INT          NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_booking_fees_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_booking_fees_type FOREIGN KEY (fee_type_id)
        REFERENCES fee_types (fee_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 30. payments
CREATE TABLE payments (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT          NOT NULL,
    method_id       INT          NOT NULL,
    status_id       INT          NOT NULL,
    currency_id     INT          NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    transaction_ref VARCHAR(60)  NOT NULL,
    paid_at         DATETIME     NULL,
    UNIQUE KEY uq_payments_transaction (transaction_ref),
    CONSTRAINT fk_payments_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_payments_method FOREIGN KEY (method_id)
        REFERENCES payment_methods (method_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_payments_status FOREIGN KEY (status_id)
        REFERENCES payment_statuses (status_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_payments_currency FOREIGN KEY (currency_id)
        REFERENCES currencies (currency_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 31. refunds
CREATE TABLE refunds (
    refund_id       INT AUTO_INCREMENT PRIMARY KEY,
    payment_id      INT          NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    reason          VARCHAR(255) NULL,
    processed_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_refunds_payment FOREIGN KEY (payment_id)
        REFERENCES payments (payment_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 32. host_payouts
CREATE TABLE host_payouts (
    payout_id       INT AUTO_INCREMENT PRIMARY KEY,
    host_id         INT          NOT NULL,
    booking_id      INT          NOT NULL,
    gross_amount    DECIMAL(10,2) NOT NULL,
    platform_fee    DECIMAL(10,2) NOT NULL,
    net_amount      DECIMAL(10,2) NOT NULL,
    payout_status   ENUM('pending','paid','failed') NOT NULL DEFAULT 'pending',
    payout_date     DATE         NULL,
    CONSTRAINT fk_payouts_host FOREIGN KEY (host_id)
        REFERENCES host_profiles (host_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_payouts_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 33. invoices
CREATE TABLE invoices (
    invoice_id      INT AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT          NOT NULL,
    invoice_number  VARCHAR(30)  NOT NULL,
    issued_date     DATE         NOT NULL,
    total_amount    DECIMAL(10,2) NOT NULL,
    tax_amount      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    pdf_url         VARCHAR(255) NULL,
    UNIQUE KEY uq_invoices_booking (booking_id),
    UNIQUE KEY uq_invoices_number  (invoice_number),
    CONSTRAINT fk_invoices_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 34. guest_verifications
CREATE TABLE guest_verifications (
    verification_id  INT AUTO_INCREMENT PRIMARY KEY,
    guest_id         INT          NOT NULL,
    status           ENUM('pending','approved','rejected','expired') NOT NULL DEFAULT 'pending',
    submitted_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at      DATETIME     NULL,
    reviewed_by      INT          NULL,
    rejection_reason VARCHAR(255) NULL,
    CONSTRAINT fk_verifications_guest FOREIGN KEY (guest_id)
        REFERENCES guest_profiles (guest_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_verifications_reviewer FOREIGN KEY (reviewed_by)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE SET NULL
);

-- 35. verification_documents
CREATE TABLE verification_documents (
    document_id     INT AUTO_INCREMENT PRIMARY KEY,
    verification_id INT          NOT NULL,
    doc_type_id     INT          NOT NULL,
    file_url        VARCHAR(255) NOT NULL,
    document_number VARCHAR(60)  NULL,
    expiry_date     DATE         NULL,
    CONSTRAINT fk_verif_docs_verification FOREIGN KEY (verification_id)
        REFERENCES guest_verifications (verification_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_verif_docs_type FOREIGN KEY (doc_type_id)
        REFERENCES id_document_types (doc_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 36. smart_devices
CREATE TABLE smart_devices (
    device_id        INT AUTO_INCREMENT PRIMARY KEY,
    property_id      INT          NOT NULL,
    device_type_id   INT          NOT NULL,
    serial_number    VARCHAR(60)  NOT NULL,
    location_label   VARCHAR(80)  NOT NULL DEFAULT 'Main door',
    battery_level    TINYINT      NULL,
    firmware_version VARCHAR(20)  NULL,
    is_online        TINYINT(1)   NOT NULL DEFAULT 1,
    installed_at     DATE         NOT NULL,
    UNIQUE KEY uq_devices_serial (serial_number),
    CONSTRAINT fk_devices_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_devices_type FOREIGN KEY (device_type_id)
        REFERENCES device_types (device_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 37. access_codes
CREATE TABLE access_codes (
    code_id         INT AUTO_INCREMENT PRIMARY KEY,
    device_id       INT          NOT NULL,
    booking_id      INT          NULL,
    code_type_id    INT          NOT NULL,
    assigned_to     INT          NULL,
    code_value      VARCHAR(12)  NOT NULL,
    valid_from      DATETIME     NOT NULL,
    valid_until     DATETIME     NOT NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_codes_device_value (device_id, code_value),
    CONSTRAINT fk_codes_device FOREIGN KEY (device_id)
        REFERENCES smart_devices (device_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_codes_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_codes_type FOREIGN KEY (code_type_id)
        REFERENCES access_code_types (code_type_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_assigned_to FOREIGN KEY (assigned_to)
        REFERENCES users (user_id) ON DELETE SET NULL
);

-- 38. access_events
-- event_id: BIGINT because this table grows with every lock interaction
-- and INT (max 2.1 billion) would eventually overflow at scale
CREATE TABLE access_events (
    event_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    device_id       INT          NOT NULL,
    code_id         INT          NULL,
    event_type      ENUM('unlock_success','unlock_failed','lock','battery_low','tamper_alert') NOT NULL,
    event_time      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    details         VARCHAR(255) NULL,
    CONSTRAINT fk_events_device FOREIGN KEY (device_id)
        REFERENCES smart_devices (device_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_events_code FOREIGN KEY (code_id)
        REFERENCES access_codes (code_id) ON UPDATE CASCADE ON DELETE SET NULL
);

-- 39. reviews
-- overall_rating: CHECK constraint enforces valid range at database level
CREATE TABLE reviews (
    review_id       INT AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT          NOT NULL,
    author_guest_id INT          NOT NULL,
    overall_rating  TINYINT      NOT NULL,
    comment         TEXT         NULL,
    is_visible      TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_reviews_booking (booking_id),
    CONSTRAINT chk_overall_rating CHECK (overall_rating BETWEEN 1 AND 5),
    CONSTRAINT fk_reviews_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_reviews_guest FOREIGN KEY (author_guest_id)
        REFERENCES guest_profiles (guest_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 40. review_scores (composite PK — one score per review per category)
-- score: CHECK constraint enforces valid range at database level
CREATE TABLE review_scores (
    review_id       INT NOT NULL,
    category_id     INT NOT NULL,
    score           TINYINT NOT NULL,
    PRIMARY KEY (review_id, category_id),
    CONSTRAINT chk_score CHECK (score BETWEEN 1 AND 5),
    CONSTRAINT fk_scores_review FOREIGN KEY (review_id)
        REFERENCES reviews (review_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_scores_category FOREIGN KEY (category_id)
        REFERENCES review_categories (category_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

-- 41. review_responses
CREATE TABLE review_responses (
    response_id     INT AUTO_INCREMENT PRIMARY KEY,
    review_id       INT          NOT NULL,
    host_id         INT          NOT NULL,
    response_text   TEXT         NOT NULL,
    responded_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_responses_review (review_id),
    CONSTRAINT fk_responses_review FOREIGN KEY (review_id)
        REFERENCES reviews (review_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_responses_host FOREIGN KEY (host_id)
        REFERENCES host_profiles (host_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 42. messages
CREATE TABLE messages (
    message_id      INT AUTO_INCREMENT PRIMARY KEY,
    booking_id      INT          NOT NULL,
    sender_id       INT          NOT NULL,
    receiver_id     INT          NOT NULL,
    message_text    TEXT         NOT NULL,
    is_read         TINYINT(1)   NOT NULL DEFAULT 0,
    sent_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_messages_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_messages_receiver FOREIGN KEY (receiver_id)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 43. maintenance_requests
-- description: TEXT instead of VARCHAR(500) — maintenance descriptions
-- have no predictable length limit
CREATE TABLE maintenance_requests (
    request_id      INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    category_id     INT          NOT NULL,
    reported_by     INT          NOT NULL,
    title           VARCHAR(120) NOT NULL,
    description     TEXT         NULL,
    request_status  ENUM('open','in_progress','resolved','cancelled') NOT NULL DEFAULT 'open',
    reported_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at     DATETIME     NULL,
    CONSTRAINT fk_maintenance_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_maintenance_category FOREIGN KEY (category_id)
        REFERENCES maintenance_categories (category_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_maintenance_reporter FOREIGN KEY (reported_by)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- 44. cleaning_tasks
CREATE TABLE cleaning_tasks (
    task_id         INT AUTO_INCREMENT PRIMARY KEY,
    property_id     INT          NOT NULL,
    booking_id      INT          NULL,
    assigned_to     INT          NULL,
    scheduled_date  DATE         NOT NULL,
    task_status     ENUM('scheduled','done','missed') NOT NULL DEFAULT 'scheduled',
    notes           VARCHAR(255) NULL,
    CONSTRAINT fk_cleaning_property FOREIGN KEY (property_id)
        REFERENCES properties (property_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_cleaning_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_cleaning_staff FOREIGN KEY (assigned_to)
        REFERENCES users (user_id) ON UPDATE CASCADE ON DELETE SET NULL
);

-- 45. promotions
CREATE TABLE promotions (
    promotion_id     INT AUTO_INCREMENT PRIMARY KEY,
    promo_code       VARCHAR(30)  NOT NULL,
    description      VARCHAR(255) NULL,
    discount_percent DECIMAL(5,2) NOT NULL,
    valid_from       DATE         NOT NULL,
    valid_until      DATE         NOT NULL,
    max_uses         INT          NULL,
    is_active        TINYINT(1)   NOT NULL DEFAULT 1,
    UNIQUE KEY uq_promotions_code (promo_code)
);

-- 46. booking_promotions (M:N bridge table — composite primary key)
CREATE TABLE booking_promotions (
    booking_id      INT          NOT NULL,
    promotion_id    INT          NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (booking_id, promotion_id),
    CONSTRAINT fk_bp_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_bp_promotion FOREIGN KEY (promotion_id)
        REFERENCES promotions (promotion_id) ON UPDATE CASCADE ON DELETE RESTRICT
);