"""
Short-Term Rental & Smart Access Management System
app.py — Console application (Python + MySQL)

Demonstrates:
  * INSERT / UPDATE / SELECT / DELETE operations
  * Multi-table JOINs and correlated + nested subqueries
  * Transactions (booking + payment + access code issued atomically)
  * Error checking and user-input validation

Requires:  pip install mysql-connector-python
Run after executing 01_schema.sql, 02_indexes_views_security.sql, 03_sample_data.sql
"""

import random
import sys
from datetime import datetime, date

try:
    import mysql.connector
    from mysql.connector import Error
except ImportError:
    sys.exit("Missing dependency. Run:  pip install mysql-connector-python")

# ---------------------------------------------------------------------
# Connection settings — adjust password/user to your local MySQL setup.
# 'app_admin' is created by 02_indexes_views_security.sql
# ---------------------------------------------------------------------
DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 3306,
    "user": "app_admin",
    "password": "Admin#2026!",
    "database": "rental_access_db",
    "autocommit": True,  # plain SELECTs auto-commit; multi-step writes use
                         # conn.start_transaction() + commit()/rollback()
}


def get_connection():
    """Open a database connection, or exit with a clear message."""
    try:
        return mysql.connector.connect(**DB_CONFIG)
    except Error as err:
        sys.exit(f"Could not connect to database: {err}")


# ------------------------- input validation --------------------------

def ask_int(prompt, min_val=1, max_val=None):
    """Ask until the user enters a valid integer in range."""
    while True:
        raw = input(prompt).strip()
        if not raw.isdigit():
            print("  Please enter a whole number.")
            continue
        value = int(raw)
        if value < min_val or (max_val is not None and value > max_val):
            print(f"  Value must be between {min_val} and {max_val or 'infinity'}.")
            continue
        return value


def ask_date(prompt):
    """Ask until the user enters a valid YYYY-MM-DD date."""
    while True:
        raw = input(prompt).strip()
        try:
            return datetime.strptime(raw, "%Y-%m-%d").date()
        except ValueError:
            print("  Please use the format YYYY-MM-DD, e.g. 2026-07-15.")


def print_rows(cursor, empty_msg="No results found."):
    """Print a result set as aligned columns."""
    rows = cursor.fetchall()
    if not rows:
        print(empty_msg)
        return
    headers = cursor.column_names
    widths = [max(len(str(h)), max(len(str(r[i])) for r in rows)) for i, h in enumerate(headers)]
    line = " | ".join(h.ljust(widths[i]) for i, h in enumerate(headers))
    print(line)
    print("-" * len(line))
    for r in rows:
        print(" | ".join(str(c).ljust(widths[i]) for i, c in enumerate(r)))


# --------------------------- features --------------------------------

def list_properties(conn):
    """SELECT with multiple JOINs through the catalog view."""
    cur = conn.cursor()
    cur.execute("""
        SELECT property_id, title, property_type, city_name, host_name,
               base_price_night, currency_code, review_count, avg_rating
        FROM v_property_catalog
        ORDER BY city_name, base_price_night
    """)
    print_rows(cur)
    cur.close()


def search_available(conn):
    """Availability search using a correlated NOT EXISTS subquery:
    a property is available if no confirmed/checked-in booking overlaps."""
    check_in = ask_date("Check-in date  (YYYY-MM-DD): ")
    check_out = ask_date("Check-out date (YYYY-MM-DD): ")
    if check_out <= check_in:
        print("Check-out must be after check-in.")
        return
    guests = ask_int("Number of guests: ", 1, 20)

    cur = conn.cursor()
    cur.execute("""
        SELECT p.property_id, p.title, c.city_name, p.max_guests, p.base_price_night
        FROM properties p
        JOIN cities c ON c.city_id = p.city_id
        WHERE p.is_active = 1
          AND p.max_guests >= %s
          AND NOT EXISTS (
                SELECT 1
                FROM bookings b
                JOIN booking_statuses bs ON bs.status_id = b.status_id
                WHERE b.property_id = p.property_id
                  AND bs.status_name IN ('pending','confirmed','checked_in')
                  AND b.check_in_date < %s     -- existing stay starts before requested end
                  AND b.check_out_date > %s    -- and ends after requested start  -> overlap
          )
        ORDER BY p.base_price_night
    """, (guests, check_out, check_in))
    print_rows(cur, "No properties available for those dates.")
    cur.close()


def create_booking(conn):
    """Transaction: insert booking + payment + access code atomically."""
    property_id = ask_int("Property ID: ")
    guest_id = ask_int("Guest user ID: ")
    check_in = ask_date("Check-in  (YYYY-MM-DD): ")
    check_out = ask_date("Check-out (YYYY-MM-DD): ")
    if check_out <= check_in:
        print("Check-out must be after check-in.")
        return
    guests = ask_int("Number of guests: ", 1, 20)

    cur = conn.cursor()
    try:
        # Validate the property and capacity
        cur.execute("""SELECT base_price_night, max_guests, currency_id
                       FROM properties WHERE property_id = %s AND is_active = 1""",
                    (property_id,))
        row = cur.fetchone()
        if row is None:
            print("No active property with that ID.")
            return
        price, max_guests, currency_id = row
        if guests > max_guests:
            print(f"This property allows at most {max_guests} guests.")
            return

        # Validate guest exists
        cur.execute("SELECT 1 FROM guest_profiles WHERE guest_id = %s", (guest_id,))
        if cur.fetchone() is None:
            print("No guest profile with that ID.")
            return

        # Reject overlapping bookings (same overlap rule as the search)
        cur.execute("""
            SELECT COUNT(*) FROM bookings b
            JOIN booking_statuses bs ON bs.status_id = b.status_id
            WHERE b.property_id = %s
              AND bs.status_name IN ('pending','confirmed','checked_in')
              AND b.check_in_date < %s AND b.check_out_date > %s
        """, (property_id, check_out, check_in))
        if cur.fetchone()[0] > 0:
            print("Those dates overlap an existing booking.")
            return

        nights = (check_out - check_in).days
        total = float(price) * nights

        conn.start_transaction()
        # 1) booking (status 'confirmed')
        cur.execute("""
            INSERT INTO bookings (property_id, guest_id, status_id, currency_id,
                                  check_in_date, check_out_date, num_guests,
                                  nightly_rate, total_amount)
            VALUES (%s, %s,
                    (SELECT status_id FROM booking_statuses WHERE status_name='confirmed'),
                    %s, %s, %s, %s, %s, %s)
        """, (property_id, guest_id, currency_id, check_in, check_out, guests, price, total))
        booking_id = cur.lastrowid

        # 2) payment (captured)
        txn_ref = f"TXN-{datetime.now():%Y%m%d%H%M%S}-{random.randint(100,999)}"
        cur.execute("""
            INSERT INTO payments (booking_id, method_id, status_id, currency_id,
                                  amount, transaction_ref, paid_at)
            VALUES (%s,
                    (SELECT method_id FROM payment_methods WHERE method_name='Credit card'),
                    (SELECT status_id FROM payment_statuses WHERE status_name='captured'),
                    %s, %s, %s, NOW())
        """, (booking_id, currency_id, total, txn_ref))

        # 3) access code on the property's main smart device (if installed)
        cur.execute("""SELECT device_id FROM smart_devices
                       WHERE property_id = %s ORDER BY device_id LIMIT 1""", (property_id,))
        device = cur.fetchone()
        code_value = None
        if device:
            code_value = f"{random.randint(0, 999999):06d}"
            cur.execute("""
                INSERT INTO access_codes (device_id, booking_id, code_type_id, code_value,
                                          valid_from, valid_until, is_active)
                VALUES (%s, %s,
                        (SELECT code_type_id FROM access_code_types
                         WHERE type_name='Guest stay code'),
                        %s, CONCAT(%s,' 15:00:00'), CONCAT(%s,' 11:00:00'), 1)
            """, (device[0], booking_id, code_value, check_in, check_out))

        conn.commit()
        print(f"Booking #{booking_id} confirmed — {nights} nights, total {total:.2f}.")
        print(f"Payment recorded ({txn_ref}).")
        if code_value:
            print(f"Door code {code_value} active from check-in 15:00 to check-out 11:00.")
        else:
            print("No smart device installed — physical key handover required.")
    except Error as err:
        conn.rollback()
        print(f"Booking failed, all changes rolled back: {err}")
    finally:
        cur.close()


def cancel_booking(conn):
    """UPDATE: cancel a booking and deactivate its access codes."""
    booking_id = ask_int("Booking ID to cancel: ")
    cur = conn.cursor()
    try:
        conn.start_transaction()
        cur.execute("""
            UPDATE bookings
            SET status_id = (SELECT status_id FROM booking_statuses
                             WHERE status_name = 'cancelled')
            WHERE booking_id = %s
        """, (booking_id,))
        if cur.rowcount == 0:
            conn.rollback()
            print("No booking with that ID.")
            return
        cur.execute("UPDATE access_codes SET is_active = 0 WHERE booking_id = %s",
                    (booking_id,))
        codes_deactivated = cur.rowcount
        conn.commit()
        print(f"Booking #{booking_id} cancelled; {codes_deactivated} access code(s) deactivated.")
    except Error as err:
        conn.rollback()
        print(f"Cancellation failed: {err}")
    finally:
        cur.close()


def add_review(conn):
    """INSERT with business-rule validation in the application layer."""
    booking_id = ask_int("Booking ID to review: ")
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT b.guest_id, bs.status_name
            FROM bookings b
            JOIN booking_statuses bs ON bs.status_id = b.status_id
            WHERE b.booking_id = %s
        """, (booking_id,))
        row = cur.fetchone()
        if row is None:
            print("No booking with that ID.")
            return
        guest_id, status = row
        if status != "completed":
            print(f"Only completed stays can be reviewed (current status: {status}).")
            return
        rating = ask_int("Overall rating (1-5): ", 1, 5)
        comment = input("Comment (optional): ").strip() or None
        cur.execute("""
            INSERT INTO reviews (booking_id, author_guest_id, overall_rating, comment)
            VALUES (%s, %s, %s, %s)
        """, (booking_id, guest_id, rating, comment))
        print(f"Review #{cur.lastrowid} saved.")
    except Error as err:
        conn.rollback()
        if err.errno == 1062:  # duplicate key — UNIQUE(booking_id)
            print("This booking already has a review.")
        else:
            print(f"Could not save review: {err}")
    finally:
        cur.close()


def top_guests(conn):
    """Nested (non-correlated) subquery: guests spending above the average
    total booking value across the whole platform."""
    cur = conn.cursor()
    cur.execute("""
        SELECT CONCAT(u.first_name,' ',u.last_name) AS guest,
               COUNT(b.booking_id)  AS bookings,
               SUM(b.total_amount)  AS total_spent
        FROM users u
        JOIN bookings b ON b.guest_id = u.user_id
        GROUP BY u.user_id, u.first_name, u.last_name
        HAVING SUM(b.total_amount) > (SELECT AVG(total_amount) FROM bookings)
        ORDER BY total_spent DESC
    """)
    print_rows(cur, "No guest is above the platform average yet.")
    cur.close()


def access_audit(conn):
    """SELECT from the security audit view (multi-join behind the scenes)."""
    cur = conn.cursor()
    cur.execute("""
        SELECT event_time, event_type, property_title, location_label,
               COALESCE(guest_name,'-') AS guest, COALESCE(code_value,'-') AS code
        FROM v_access_audit
        ORDER BY event_time DESC
        LIMIT 15
    """)
    print_rows(cur)
    cur.close()


def purge_expired_codes(conn):
    """DELETE: remove inactive codes whose validity window has fully passed."""
    cur = conn.cursor()
    try:
        cur.execute("""
            DELETE FROM access_codes
            WHERE is_active = 0 AND valid_until < NOW()
        """)
        conn.commit()
        print(f"Deleted {cur.rowcount} expired access code(s).")
    except Error as err:
        conn.rollback()
        print(f"Delete failed: {err}")
    finally:
        cur.close()


def upcoming_checkins(conn):
    """Operations view: who arrives in the next 60 days and are they ready."""
    cur = conn.cursor()
    cur.execute("""
        SELECT b.booking_id, b.check_in_date, p.title AS property_title,
               CONCAT(u.first_name, ' ', u.last_name) AS guest_name,
               bs.status_name AS booking_status,
               (SELECT gv.status
                  FROM guest_verifications gv
                 WHERE gv.guest_id = b.guest_id
                 ORDER BY gv.submitted_at DESC
                 LIMIT 1)   AS verification_status,
               (SELECT COUNT(*)
                  FROM access_codes ac
                 WHERE ac.booking_id = b.booking_id
                   AND ac.is_active = 1) AS active_codes
        FROM bookings b
        JOIN properties p        ON p.property_id = b.property_id
        JOIN users u             ON u.user_id = b.guest_id
        JOIN booking_statuses bs ON bs.status_id = b.status_id
        WHERE b.check_in_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 60 DAY)
          AND bs.status_name IN ('confirmed', 'pending')
        ORDER BY b.check_in_date
    """)
    print_rows(cur, "No check-ins in the next 60 days.")
    cur.close()


MENU = """
================ Rental & Smart Access Manager ================
 1. List all properties (catalog with ratings)
 2. Search availability for a date range
 3. Create booking (+ payment + door code)   [transaction]
 4. Cancel booking (deactivates door codes)  [update]
 5. Add a stay review                        [insert + rules]
 6. Above-average spending guests            [subquery]
 7. Access event audit log                   [view / joins]
 8. Purge expired access codes               [delete]
 9. Upcoming check-ins (next 60 days)        [view]
 0. Exit
================================================================
"""


def main():
    conn = get_connection()
    actions = {
        "1": list_properties, "2": search_available, "3": create_booking,
        "4": cancel_booking, "5": add_review, "6": top_guests,
        "7": access_audit, "8": purge_expired_codes, "9": upcoming_checkins,
    }
    print("Connected to rental_access_db.")
    while True:
        print(MENU)
        choice = input("Choose an option: ").strip()
        if choice == "0":
            break
        action = actions.get(choice)
        if action is None:
            print("Invalid option, please choose 0-9.")
            continue
        try:
            action(conn)
        except (KeyboardInterrupt, EOFError):
            print("\nAction cancelled.")
    conn.close()
    print("Goodbye!")


if __name__ == "__main__":
    main()