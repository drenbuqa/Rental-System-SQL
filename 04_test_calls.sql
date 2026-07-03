-- =====================================================================
-- Short-Term Rental & Smart Access Management System
-- 05_test_calls.sql — Example stored procedure calls for local testing
-- Run this file after 01_schema.sql, 02_indexes_views_roles_transactions.sql,
-- and 03_sample_data.sql have been executed successfully.
-- =====================================================================
USE rental_access_db;

-- Test 1: Create a new booking
-- Guest Mia Holz (guest_id=7) books the Vienna Penthouse (property_id=2)
-- for 4 nights. Expects: SUCCESS with a new booking_id.
CALL sp_create_booking(2, 7, '2026-08-01', '2026-08-05', 2, 320.00, 1410.00,
    'High floor preferred if possible', @booking_id, @msg);
SELECT @booking_id AS new_booking_id, @msg AS result;

-- Test 2: Confirm the booking and issue an access code
-- Confirms the booking created above and issues code to device_id=1.
-- Expects: SUCCESS: booking confirmed and access code issued.
CALL sp_confirm_booking(@booking_id, 1, '112233', @msg);
SELECT @msg AS result;

-- Test 3: Cancel a booking with refund
-- Cancels booking_id=4 under Moderate policy (50% refund).
-- Expects: SUCCESS if booking is pending or confirmed.
CALL sp_cancel_booking(4, 4, 765.00,
    'Guest cancellation - 50% refund under Moderate policy', @msg);
SELECT @msg AS result;

-- Test 4: Complete a stay and process host payout
-- First update the booking status to checked_in, then complete it.
-- Expects: SUCCESS with payout amount calculated at 12% platform fee.
UPDATE bookings
SET status_id = (SELECT status_id FROM booking_statuses WHERE status_name = 'checked_in')
WHERE booking_id = @booking_id;

CALL sp_complete_stay(@booking_id, 1, @msg);
SELECT @msg AS result;

-- Test 5: Assign a cleaner to an access code
-- Assigns Ivan the cleaner (user_id=10) to code_id=5 for post-checkout clean.
-- Expects: SUCCESS: cleaner assigned and code activated.
CALL sp_assign_cleaner_code(5, 10,
    '2026-04-14 11:00:00', '2026-04-14 20:00:00', @msg);
SELECT @msg AS result;

-- Test 6: Verify overlap prevention
-- Attempts to book the same property and dates as Test 1.
-- Expects: ERROR: property already booked for the requested dates.
CALL sp_create_booking(2, 5, '2026-08-01', '2026-08-05', 2, 320.00, 1410.00,
    NULL, @booking_id2, @msg);
SELECT @booking_id2 AS new_booking_id, @msg AS result;