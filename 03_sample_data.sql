-- =====================================================================
-- Short-Term Rental & Smart Access Management System
-- 03_sample_data.sql — Meaningful sample data for ALL 46 tables
-- =====================================================================
USE rental_access_db;

-- ---------- Reference data ----------
INSERT INTO countries (country_name, iso_code) VALUES
('Austria','AT'),('Germany','DE'),('Italy','IT'),
('Spain','ES'),('France','FR'),('Netherlands','NL');

INSERT INTO cities (country_id, city_name, postal_region) VALUES
(1,'Vienna','1010-1230'),(1,'Salzburg','5020'),(1,'Linz','4020'),
(2,'Berlin','10115'),(2,'Munich','80331'),
(3,'Rome','00100'),(4,'Barcelona','08001'),(5,'Paris','75001');

INSERT INTO currencies (currency_code, currency_name) VALUES
('EUR','Euro'),('USD','US Dollar'),('GBP','British Pound');

INSERT INTO languages (language_code, language_name) VALUES
('en','English'),('de','German'),('it','Italian'),('es','Spanish');

INSERT INTO property_types (type_name, description) VALUES
('Apartment','Self-contained unit in a residential building'),
('Studio','Single open-plan living unit'),
('House','Entire stand-alone house'),
('Loft','Converted industrial-style open space'),
('Penthouse','Top-floor luxury unit with terrace');

INSERT INTO room_types (type_name) VALUES
('Bedroom'),('Living room'),('Kitchen'),('Bathroom'),('Office');

INSERT INTO amenities (amenity_name, category) VALUES
('Wi-Fi','Connectivity'),('Air conditioning','Comfort'),('Heating','Comfort'),
('Washing machine','Appliances'),('Dishwasher','Appliances'),
('Free parking','Outdoor'),('Balcony','Outdoor'),('Elevator','Building'),
('Smart TV','Entertainment'),('Workspace','Work');

INSERT INTO cancellation_policies (policy_name, free_cancel_days, refund_percent, description) VALUES
('Flexible',1,100.00,'Full refund up to 1 day before check-in'),
('Moderate',5,50.00,'50% refund up to 5 days before check-in'),
('Strict',14,0.00,'No refund within 14 days of check-in');

INSERT INTO booking_statuses (status_name) VALUES
('pending'),('confirmed'),('checked_in'),('completed'),('cancelled');

INSERT INTO payment_methods (method_name) VALUES
('Credit card'),('PayPal'),('Bank transfer'),('Apple Pay');

INSERT INTO payment_statuses (status_name) VALUES
('initiated'),('authorized'),('captured'),('failed');

INSERT INTO fee_types (fee_name, is_percentage, default_amount) VALUES
('Cleaning fee',0,45.00),('Service fee',1,12.00),
('City tax',1,3.20),('Pet fee',0,25.00);

INSERT INTO id_document_types (type_name) VALUES
('Passport'),('National ID card'),('Driving licence');

INSERT INTO device_types (type_name, manufacturer) VALUES
('Smart lock keypad','Nuki'),
('Bluetooth deadbolt','August'),
('Lockbox with PIN','MasterLock');

INSERT INTO access_code_types (type_name, max_uses) VALUES
('Guest stay code',NULL),
('One-time cleaner code',1),
('Maintenance code',10);

INSERT INTO review_categories (category_name) VALUES
('Cleanliness'),('Accuracy'),('Check-in'),('Communication'),('Location');

INSERT INTO maintenance_categories (category_name, priority_level) VALUES
('Plumbing',1),('Electrical',1),('Appliance',2),('Cosmetic',3);

-- ---------- Users & profiles ----------
INSERT INTO users (email, password_hash, first_name, last_name, phone,
    preferred_language_id, account_role) VALUES
('anna.gruber@example.com',  'hash$1','Anna','Gruber',  '+43 660 1111111',2,'host'),
('marco.rossi@example.com',  'hash$2','Marco','Rossi',  '+39 333 2222222',3,'host'),
('lena.koch@example.com',    'hash$3','Lena','Koch',    '+49 170 3333333',2,'host'),
('tom.baker@example.com',    'hash$4','Tom','Baker',    '+44 7700 444444',1,'guest'),
('sara.weiss@example.com',   'hash$5','Sara','Weiss',   '+43 664 5555555',2,'guest'),
('diego.lopez@example.com',  'hash$6','Diego','Lopez',  '+34 600 666666',4,'guest'),
('mia.holz@example.com',     'hash$7','Mia','Holz',     '+43 699 7777777',2,'guest'),
('john.smith@example.com',   'hash$8','John','Smith',   '+1 555 8888888',1,'guest'),
('admin@rentalaccess.com',   'hash$9','Petra','Admin',  '+43 1 9999999',1,'admin'),
('cleaner@rentalaccess.com', 'hash$10','Ivan','Cleaner','+43 676 1010101',1,'staff');

INSERT INTO host_profiles (host_id, company_name, tax_number, payout_iban, is_superhost, joined_date) VALUES
(1,'Gruber Stays GmbH','ATU12345678','AT611904300234573201',1,'2022-03-15'),
(2,NULL,'IT98765432109','IT60X0542811101000000123456',0,'2023-07-01'),
(3,'Koch Apartments','DE123456789','DE89370400440532013000',1,'2021-11-20');

INSERT INTO guest_profiles (guest_id, date_of_birth, nationality_country_id, emergency_contact) VALUES
(4,'1990-04-12',NULL,'Emily Baker +44 7700 999999'),
(5,'1998-09-03',1,'Karl Weiss +43 664 1212121'),
(6,'1985-01-27',4,'Lucia Lopez +34 600 131313'),
(7,'2000-06-18',1,'Hans Holz +43 699 141414'),
(8,'1979-12-05',NULL,'Jane Smith +1 555 151515');

-- ---------- Properties & related ----------
INSERT INTO properties (host_id, property_type_id, city_id, currency_id,
    cancellation_policy_id, title, description, street_address,
    latitude, longitude, max_guests, bedrooms, bathrooms,
    base_price_night, cleaning_fee) VALUES
(1,1,1,1,1,'Cozy Old-Town Apartment near Stephansdom',
    'Charming 2-room apartment in the heart of Vienna.',
    'Singerstrasse 12, 1010 Vienna',48.207100,16.374500,4,2,1,120.00,45.00),
(1,5,1,1,3,'Skyline Penthouse with Terrace',
    'Luxury penthouse, panoramic views over the Danube.',
    'Donaustrasse 88, 1020 Vienna',48.219000,16.401200,6,3,2,320.00,80.00),
(2,2,6,1,2,'Trastevere Artist Studio',
    'Bright studio in the liveliest district of Rome.',
    'Via della Lungaretta 5, Rome',41.889800,12.469700,2,1,1,95.00,30.00),
(3,3,4,1,2,'Family House with Garden in Berlin',
    'Quiet house, perfect for families, 15 min to centre.',
    'Gartenweg 7, 12203 Berlin',52.435600,13.318900,8,4,2,210.00,60.00),
(3,4,5,1,1,'Industrial Loft Munich Centre',
    'Stylish loft near Marienplatz with workspace.',
    'Sendlinger Strasse 21, Munich',48.135100,11.567900,3,1,1,150.00,40.00);

INSERT INTO property_photos (property_id, file_url, caption, sort_order, is_cover) VALUES
(1,'/img/p1_living.jpg','Living room',1,1),
(1,'/img/p1_bed.jpg','Master bedroom',2,0),
(2,'/img/p2_terrace.jpg','Terrace view',1,1),
(2,'/img/p2_kitchen.jpg','Open kitchen',2,0),
(3,'/img/p3_studio.jpg','Studio overview',1,1),
(4,'/img/p4_garden.jpg','Garden',1,1),
(4,'/img/p4_kids.jpg','Kids room',2,0),
(5,'/img/p5_loft.jpg','Main space',1,1);

INSERT INTO property_amenities (property_id, amenity_id) VALUES
(1,1),(1,3),(1,4),(1,8),
(2,1),(2,2),(2,7),(2,9),(2,10),
(3,1),(3,3),
(4,1),(4,4),(4,5),(4,6),
(5,1),(5,2),(5,10);

INSERT INTO property_rooms (property_id, room_type_id, room_name, size_sqm, max_occupancy) VALUES
(1,1,'Master bedroom',16.50,2),(1,1,'Guest bedroom',12.00,2),(1,2,'Living room',22.00,2),
(2,1,'Suite 1',20.00,2),(2,1,'Suite 2',18.00,2),(2,2,'Panorama lounge',35.00,4),
(3,2,'Studio space',28.00,2),
(4,1,'Parents room',18.00,2),(4,1,'Kids room 1',14.00,2),
(5,2,'Loft space',45.00,3);

INSERT INTO seasonal_pricing (property_id, season_name, start_date, end_date, nightly_price, min_nights) VALUES
(1,'Christmas market season','2026-11-20','2026-12-26',165.00,3),
(2,'New Year premium','2026-12-28','2027-01-03',450.00,4),
(3,'Summer high season','2026-06-15','2026-08-31',130.00,2),
(4,'Berlin fair weeks','2026-09-01','2026-09-20',260.00,2);

INSERT INTO availability_calendar (property_id, calendar_date, is_available, price_override) VALUES
(1,'2026-07-01',1,NULL),(1,'2026-07-02',1,NULL),(1,'2026-07-03',0,NULL),
(2,'2026-07-10',1,350.00),(2,'2026-07-11',1,350.00),
(3,'2026-06-20',0,NULL),(3,'2026-06-21',0,NULL),
(4,'2026-08-15',1,NULL),
(5,'2026-07-05',1,160.00),(5,'2026-07-06',1,160.00);

-- ---------- Bookings & money ----------
INSERT INTO bookings (property_id, guest_id, status_id, currency_id,
    check_in_date, check_out_date, num_guests, nightly_rate,
    total_amount, special_requests) VALUES
(1,4,4,1,'2026-04-10','2026-04-14',2,120.00,525.00,'Late check-in around 22:00'),
(2,5,2,1,'2026-06-15','2026-06-20',4,320.00,1680.00,NULL),
(3,6,2,1,'2026-06-12','2026-06-16',2,95.00,410.00,'Ground floor preferred'),
(4,7,1,1,'2026-07-01','2026-07-08',6,210.00,1530.00,'Travelling with a dog'),
(1,8,5,1,'2026-05-02','2026-05-05',2,120.00,405.00,NULL),
(5,4,2,1,'2026-06-14','2026-06-17',2,150.00,490.00,'Need a desk for remote work');

INSERT INTO booking_guests (booking_id, full_name, date_of_birth, is_primary) VALUES
(1,'Tom Baker','1990-04-12',1),(1,'Emily Baker','1992-08-30',0),
(2,'Sara Weiss','1998-09-03',1),(2,'Karl Weiss','1996-02-11',0),
(3,'Diego Lopez','1985-01-27',1),
(4,'Mia Holz','2000-06-18',1),(4,'Hans Holz','1972-03-22',0),
(6,'Tom Baker','1990-04-12',1);

INSERT INTO booking_fees (booking_id, fee_type_id, amount) VALUES
(1,1,45.00),(1,3,14.40),
(2,1,80.00),(2,2,192.00),
(3,1,30.00),
(4,1,60.00),(4,4,25.00),
(6,1,40.00);

INSERT INTO payments (booking_id, method_id, status_id, currency_id,
    amount, transaction_ref, paid_at) VALUES
(1,1,3,1,525.00,'TXN-2026-0001','2026-03-20 14:32:00'),
(2,2,3,1,1680.00,'TXN-2026-0002','2026-05-10 09:15:00'),
(3,1,3,1,410.00,'TXN-2026-0003','2026-05-22 18:40:00'),
(4,3,1,1,1530.00,'TXN-2026-0004',NULL),
(5,1,3,1,405.00,'TXN-2026-0005','2026-04-01 11:05:00'),
(6,4,3,1,490.00,'TXN-2026-0006','2026-05-30 16:20:00');

INSERT INTO refunds (payment_id, amount, reason) VALUES
(5,202.50,'Cancellation under Flexible policy — 50% goodwill refund');

INSERT INTO host_payouts (host_id, booking_id, gross_amount, platform_fee,
    net_amount, payout_status, payout_date) VALUES
(1,1,525.00,63.00,462.00,'paid','2026-04-16'),
(1,2,1680.00,201.60,1478.40,'pending',NULL),
(2,3,410.00,49.20,360.80,'pending',NULL),
(3,6,490.00,58.80,431.20,'paid','2026-06-19');

INSERT INTO invoices (booking_id, invoice_number, issued_date,
    total_amount, tax_amount, pdf_url) VALUES
(1,'INV-2026-0001','2026-04-14',525.00,87.50,'/invoices/INV-2026-0001.pdf'),
(2,'INV-2026-0002','2026-05-10',1680.00,280.00,'/invoices/INV-2026-0002.pdf'),
(3,'INV-2026-0003','2026-05-22',410.00,68.33,'/invoices/INV-2026-0003.pdf'),
(6,'INV-2026-0004','2026-05-30',490.00,81.67,'/invoices/INV-2026-0004.pdf');

-- ---------- Verification ----------
INSERT INTO guest_verifications (guest_id, status, submitted_at,
    reviewed_at, reviewed_by, rejection_reason) VALUES
(4,'approved','2026-03-18 10:00:00','2026-03-18 15:30:00',9,NULL),
(5,'approved','2026-05-08 12:00:00','2026-05-09 09:00:00',9,NULL),
(6,'pending','2026-06-01 08:45:00',NULL,NULL,NULL),
(7,'rejected','2026-06-02 19:20:00','2026-06-03 10:10:00',9,'Document photo unreadable'),
(8,'approved','2026-04-20 13:00:00','2026-04-20 17:45:00',9,NULL);

INSERT INTO verification_documents (verification_id, doc_type_id, file_url,
    document_number, expiry_date) VALUES
(1,1,'/docs/v1_passport.jpg','P1234567','2031-05-01'),
(2,2,'/docs/v2_id.jpg','ID998877','2029-09-15'),
(3,1,'/docs/v3_passport.jpg','XDA445566','2028-01-30'),
(4,3,'/docs/v4_licence.jpg','DL-2210-AA','2027-06-18'),
(5,1,'/docs/v5_passport.jpg','US7755331','2030-11-02');

-- ---------- Smart access ----------
INSERT INTO smart_devices (property_id, device_type_id, serial_number,
    location_label, battery_level, firmware_version, is_online, installed_at) VALUES
(1,1,'NUKI-AA-1001','Main door',86,'3.2.1',1,'2024-02-10'),
(2,1,'NUKI-AA-1002','Main door',91,'3.2.1',1,'2024-05-22'),
(2,2,'AUG-BB-2001','Terrace door',64,'2.8.0',1,'2024-05-22'),
(3,3,'ML-CC-3001','Entrance lockbox',NULL,NULL,1,'2023-09-01'),
(4,1,'NUKI-AA-1003','Front door',23,'3.1.9',0,'2024-08-14');

INSERT INTO access_codes (device_id, booking_id, code_type_id, code_value,
    valid_from, valid_until, is_active) VALUES
(1,1,1,'481972','2026-04-10 15:00:00','2026-04-14 11:00:00',0),
(2,2,1,'765230','2026-06-15 15:00:00','2026-06-20 11:00:00',1),
(3,2,1,'765230','2026-06-15 15:00:00','2026-06-20 11:00:00',1),
(4,3,1,'330011','2026-06-12 14:00:00','2026-06-16 10:00:00',1),
(1,NULL,2,'907788','2026-04-14 11:00:00','2026-04-14 17:00:00',0),
(5,NULL,3,'556644','2026-06-01 08:00:00','2026-06-30 20:00:00',1);

INSERT INTO access_events (device_id, code_id, event_type, event_time, details) VALUES
(1,1,'unlock_success','2026-04-10 22:14:03','First guest entry'),
(1,1,'lock','2026-04-10 22:14:40',NULL),
(1,1,'unlock_success','2026-04-11 09:02:11',NULL),
(1,5,'unlock_success','2026-04-14 12:05:50','Cleaner entry'),
(1,NULL,'unlock_failed','2026-04-15 02:31:07','Unknown code 111111 attempted 3x'),
(5,NULL,'battery_low','2026-06-05 06:00:00','Battery at 23%'),
(2,2,'unlock_success','2026-06-15 15:42:19','Guest self check-in'),
(4,4,'unlock_success','2026-06-12 14:30:00','Lockbox opened');

-- ---------- Reviews ----------
INSERT INTO reviews (booking_id, author_guest_id, overall_rating, comment) VALUES
(1,4,5,'Fantastic location and the keypad check-in was effortless.'),
(3,6,4,'Lovely studio, slightly noisy at night but great host.'),
(5,8,3,'Booking was cancelled, but the host handled the refund fairly.'),
(6,4,5,'Perfect for remote work, fast Wi-Fi and a great desk.');

INSERT INTO review_scores (review_id, category_id, score) VALUES
(1,1,5),(1,2,5),(1,3,5),(1,4,5),(1,5,5),
(2,1,4),(2,2,4),(2,3,5),(2,5,3),
(4,1,5),(4,3,5),(4,4,5);

INSERT INTO review_responses (review_id, host_id, response_text) VALUES
(1,1,'Thank you Tom! You are welcome back any time.'),
(2,2,'Grazie Diego! We are adding soundproof windows this autumn.');

-- ---------- Communication & operations ----------
INSERT INTO messages (booking_id, sender_id, receiver_id, message_text, is_read) VALUES
(1,4,1,'Hi Anna, we will arrive around 22:00 — is self check-in okay?',1),
(1,1,4,'Of course! Your door code becomes active at 15:00 on arrival day.',1),
(2,5,1,'Is the terrace furniture available in June?',1),
(2,1,5,'Yes, fully set up with sun loungers.',0),
(4,7,3,'We are bringing a small dog, I added the pet fee.',1),
(6,4,3,'Could you confirm the desk has a monitor?',0);

INSERT INTO maintenance_requests (property_id, category_id, reported_by,
    title, description, request_status, resolved_at) VALUES
(4,2,3,'Front door lock offline',
    'Smart lock lost Wi-Fi connection and battery is low.','in_progress',NULL),
(1,1,1,'Dripping bathroom tap',
    'Slow drip in the main bathroom sink.','resolved','2026-05-12 16:00:00'),
(2,3,1,'Dishwasher error E4',
    'Dishwasher stops mid-cycle with error E4.','open',NULL);

INSERT INTO cleaning_tasks (property_id, booking_id, assigned_to,
    scheduled_date, task_status, notes) VALUES
(1,1,10,'2026-04-14','done','Standard turnover clean'),
(2,2,10,'2026-06-20','scheduled','Deep clean incl. terrace'),
(3,3,10,'2026-06-16','scheduled',NULL),
(5,6,10,'2026-06-17','scheduled','Check desk equipment');

INSERT INTO promotions (promo_code, description, discount_percent,
    valid_from, valid_until, max_uses, is_active) VALUES
('SUMMER26','Summer 2026 launch discount',10.00,'2026-05-01','2026-08-31',500,1),
('LONGSTAY','5+ nights long-stay discount',15.00,'2026-01-01','2026-12-31',NULL,1);

INSERT INTO booking_promotions (booking_id, promotion_id, discount_amount) VALUES
(2,1,168.00),
(4,2,229.50);