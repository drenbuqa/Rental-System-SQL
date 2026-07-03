from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from db import query, callproc
from routes.auth import login_required
from datetime import date
import mysql.connector

guest_bp = Blueprint("guest", __name__)


@guest_bp.route("/")
@login_required("guest")
def dashboard():
    uid = session["user_id"]
    upcoming = query(
        "SELECT COUNT(*) AS n FROM v_guest_booking_history "
        "WHERE user_id=%s AND booking_status IN ('confirmed','pending') AND check_in_date >= CURDATE()",
        (uid,), fetchone=True)["n"]
    spent = query(
        "SELECT COALESCE(SUM(total_amount),0) AS n FROM v_guest_booking_history WHERE user_id=%s",
        (uid,), fetchone=True)["n"]
    codes = query(
        "SELECT COUNT(*) AS n FROM access_codes ac "
        "JOIN bookings b ON ac.booking_id=b.booking_id "
        "WHERE b.guest_id=%s AND ac.is_active=1 AND ac.valid_until >= NOW()",
        (uid,), fetchone=True)["n"]
    return render_template("guest/dashboard.html", upcoming=upcoming, spent=spent, codes=codes)


@guest_bp.route("/search")
@login_required("guest")
def search():
    city      = request.args.get("city", "").strip()
    check_in  = request.args.get("check_in", "")
    check_out = request.args.get("check_out", "")
    guests    = request.args.get("guests", "")
    properties = []
    cities = [r["city_name"] for r in query("SELECT city_name FROM cities ORDER BY city_name")]

    try:
        if city or check_in or check_out or guests:
            # Filtered search
            params = []
            sql = "SELECT pc.* FROM v_property_catalog pc WHERE 1=1"
            if city:
                sql += " AND pc.city_name=%s"; params.append(city)
            if guests:
                sql += " AND pc.max_guests >= %s"; params.append(int(guests))
            if check_in and check_out:
                sql += (" AND NOT EXISTS ("
                        "  SELECT 1 FROM bookings b "
                        "  JOIN booking_statuses bs ON b.status_id=bs.status_id "
                        "  WHERE b.property_id=pc.property_id "
                        "  AND bs.status_name NOT IN ('cancelled','completed') "
                        "  AND b.check_in_date < %s AND b.check_out_date > %s"
                        ")")
                params += [check_out, check_in]
            sql += " ORDER BY pc.avg_rating DESC"
            properties = query(sql, tuple(params))
        else:
            properties = query("SELECT * FROM v_property_catalog ORDER BY avg_rating DESC")
    except (mysql.connector.Error, ValueError) as e:
        flash(f"Search error: {e}", "danger")

    amenities_map = {}
    photos_map = {}
    if properties:
        prop_ids = [p["property_id"] for p in properties]
        placeholders = ",".join(["%s"] * len(prop_ids))
        amen_rows = query(
            f"SELECT pa.property_id, a.amenity_name FROM property_amenities pa "
            f"JOIN amenities a ON pa.amenity_id=a.amenity_id "
            f"WHERE pa.property_id IN ({placeholders})",
            tuple(prop_ids)
        )
        for row in amen_rows:
            amenities_map.setdefault(row["property_id"], []).append(row["amenity_name"])

        photo_rows = query(
            f"SELECT property_id, file_url FROM property_photos "
            f"WHERE property_id IN ({placeholders}) AND is_cover=1",
            tuple(prop_ids)
        )
        photos_map = {p["property_id"]: p["file_url"] for p in photo_rows}

    return render_template("guest/search.html", properties=properties, cities=cities,
                           city=city, check_in=check_in, check_out=check_out, guests=guests,
                           amenities_map=amenities_map, photos_map=photos_map)


@guest_bp.route("/bookings")
@login_required("guest")
def bookings():
    rows = query(
        "SELECT v.*, "
        "  (SELECT COUNT(*) FROM reviews r WHERE r.booking_id = v.booking_id) AS has_review "
        "FROM v_guest_booking_history v WHERE user_id=%s ORDER BY check_in_date DESC",
        (session["user_id"],)
    )
    return render_template("guest/bookings.html", bookings=rows)


@guest_bp.route("/book/<int:property_id>", methods=["GET", "POST"])
@login_required("guest")
def book(property_id):
    prop = query("SELECT * FROM v_property_catalog WHERE property_id=%s",
                 (property_id,), fetchone=True)
    if not prop:
        flash("Property not found.", "warning")
        return redirect(url_for("guest.search"))

    payment_methods = query("SELECT method_id, method_name FROM payment_methods ORDER BY method_id")

    # Step 1 submitted → validate dates, show step 2
    if request.method == "POST" and request.form.get("step") == "1":
        check_in  = request.form.get("check_in", "")
        check_out = request.form.get("check_out", "")
        num_guests = request.form.get("num_guests", "1")
        special    = request.form.get("special_requests", "")
        try:
            ci = date.fromisoformat(check_in)
            co = date.fromisoformat(check_out)
            nights = (co - ci).days
            if nights <= 0:
                raise ValueError("Check-out must be after check-in.")
            if int(num_guests) < 1 or int(num_guests) > prop["max_guests"]:
                raise ValueError(f"Guests must be between 1 and {prop['max_guests']}.")
            nightly  = float(prop["base_price_night"])
            cleaning = float(prop["cleaning_fee"] or 0)
            total    = round(nightly * nights + cleaning, 2)
            booking_data = dict(check_in=check_in, check_out=check_out,
                                num_guests=num_guests, special_requests=special,
                                nights=nights, nightly=nightly, cleaning=cleaning, total=total)
            return render_template("guest/book.html", prop=prop, step=2,
                                   booking_data=booking_data, payment_methods=payment_methods)
        except ValueError as e:
            flash(str(e), "danger")

    # Step 2 submitted → create booking + payment
    if request.method == "POST" and request.form.get("step") == "2":
        check_in   = request.form.get("check_in")
        check_out  = request.form.get("check_out")
        num_guests = request.form.get("num_guests", "1")
        special    = request.form.get("special_requests", "")
        method_id  = request.form.get("method_id")
        try:
            ci = date.fromisoformat(check_in)
            co = date.fromisoformat(check_out)
            nights   = (co - ci).days
            nightly  = float(prop["base_price_night"])
            cleaning = float(prop["cleaning_fee"] or 0)
            total    = round(nightly * nights + cleaning, 2)

            # Call stored procedure
            args = (property_id, session["user_id"], check_in, check_out,
                    int(num_guests), nightly, total, special or None, None, None)
            out, _ = callproc("sp_create_booking", args)
            booking_id = out[8]
            msg        = out[9]

            if not booking_id:
                flash(msg or "Booking failed — dates may be unavailable.", "danger")
                booking_data = dict(check_in=check_in, check_out=check_out,
                                    num_guests=num_guests, special_requests=special,
                                    nights=nights, nightly=nightly, cleaning=cleaning, total=total)
                return render_template("guest/book.html", prop=prop, step=2,
                                       booking_data=booking_data, payment_methods=payment_methods)

            # Record payment as 'captured'
            captured_id = query(
                "SELECT status_id FROM payment_statuses WHERE status_name='captured'",
                fetchone=True)["status_id"]
            currency_id = query(
                "SELECT currency_id FROM currencies WHERE currency_code=%s",
                (prop["currency_code"],), fetchone=True)
            currency_id = currency_id["currency_id"] if currency_id else 1

            query(
                "INSERT INTO payments (booking_id, method_id, status_id, currency_id, amount, "
                "transaction_ref, paid_at) VALUES (%s,%s,%s,%s,%s,%s,NOW())",
                (booking_id, int(method_id), captured_id, currency_id, total,
                 f"TXN-{booking_id:06d}"), commit=True
            )

            return redirect(url_for("guest.booking_confirmed",
                booking_id=booking_id, prop_title=prop["title"],
                check_in=check_in, check_out=check_out,
                num_guests=num_guests, total=total))

        except (mysql.connector.Error, ValueError) as e:
            flash(f"Error: {e}", "danger")

    # GET: step 1
    check_in  = request.args.get("check_in", "")
    check_out = request.args.get("check_out", "")
    return render_template("guest/book.html", prop=prop, step=1,
                           check_in=check_in, check_out=check_out,
                           booking_data=None, payment_methods=payment_methods)


@guest_bp.route("/booking-confirmed")
@login_required("guest")
def booking_confirmed():
    return render_template("guest/booking_confirmed.html",
        booking_id=request.args.get("booking_id"),
        prop_title=request.args.get("prop_title"),
        check_in=request.args.get("check_in"),
        check_out=request.args.get("check_out"),
        num_guests=request.args.get("num_guests"),
        total=float(request.args.get("total", 0))
    )


@guest_bp.route("/review/<int:booking_id>", methods=["GET", "POST"])
@login_required("guest")
def review(booking_id):
    booking = query(
        "SELECT * FROM v_guest_booking_history WHERE booking_id=%s AND user_id=%s",
        (booking_id, session["user_id"]), fetchone=True
    )
    if not booking or booking["booking_status"] != "completed":
        flash("Review not available for this booking.", "warning")
        return redirect(url_for("guest.bookings"))

    existing = query("SELECT review_id FROM reviews WHERE booking_id=%s", (booking_id,), fetchone=True)
    if existing:
        flash("You have already reviewed this booking.", "info")
        return redirect(url_for("guest.bookings"))

    categories = query("SELECT category_id, category_name FROM review_categories ORDER BY category_id")

    if request.method == "POST":
        rating  = request.form.get("overall_rating")
        comment = request.form.get("comment", "").strip()
        if not rating or not comment:
            flash("Please provide a rating and comment.", "warning")
        else:
            try:
                query(
                    "INSERT INTO reviews (booking_id, author_guest_id, overall_rating, "
                    "comment, is_visible, created_at) VALUES (%s,%s,%s,%s,1,NOW())",
                    (booking_id, session["user_id"], int(rating), comment), commit=True
                )
                new_review = query("SELECT review_id FROM reviews WHERE booking_id=%s",
                                   (booking_id,), fetchone=True)
                for cat in categories:
                    score = request.form.get(f"cat_{cat['category_id']}")
                    if score:
                        query(
                            "INSERT INTO review_scores (review_id, category_id, score) VALUES (%s,%s,%s)",
                            (new_review["review_id"], cat["category_id"], int(score)), commit=True
                        )
                flash("Review submitted — thank you!", "success")
                return redirect(url_for("guest.my_reviews"))
            except mysql.connector.Error as e:
                flash(f"Could not submit review: {e}", "danger")

    return render_template("guest/review.html", booking=booking, categories=categories)


@guest_bp.route("/my-reviews")
@login_required("guest")
def my_reviews():
    reviews = query(
        "SELECT r.review_id, r.overall_rating, r.comment, r.created_at, "
        "       p.title AS property_title, b.check_in_date, b.check_out_date "
        "FROM reviews r "
        "JOIN bookings b ON r.booking_id = b.booking_id "
        "JOIN properties p ON b.property_id = p.property_id "
        "WHERE r.author_guest_id = %s ORDER BY r.created_at DESC",
        (session["user_id"],)
    )
    scores_raw = query(
        "SELECT rs.review_id, rc.category_name, rs.score "
        "FROM review_scores rs "
        "JOIN review_categories rc ON rs.category_id = rc.category_id "
        "WHERE rs.review_id IN ("
        "  SELECT review_id FROM reviews WHERE author_guest_id=%s"
        ")",
        (session["user_id"],)
    )
    scores_map = {}
    for s in scores_raw:
        scores_map.setdefault(s["review_id"], {})[s["category_name"]] = s["score"]

    responses = query(
        "SELECT rr.review_id, rr.response_text, rr.responded_at, "
        "       CONCAT(u.first_name,' ',u.last_name) AS host_name "
        "FROM review_responses rr "
        "JOIN users u ON rr.host_id = u.user_id "
        "WHERE rr.review_id IN ("
        "  SELECT review_id FROM reviews WHERE author_guest_id=%s"
        ")",
        (session["user_id"],)
    )
    responses_map = {r["review_id"]: r for r in responses}

    return render_template("guest/my_reviews.html",
                           reviews=reviews, scores_map=scores_map, responses_map=responses_map)


@guest_bp.route("/access-codes")
@login_required("guest")
def access_codes():
    rows = query(
        "SELECT ac.code_value, ac.valid_from, ac.valid_until, ac.is_active, "
        "sd.location_label, sd.serial_number, p.title AS property_title, "
        "b.check_in_date, b.check_out_date "
        "FROM access_codes ac "
        "JOIN bookings b ON ac.booking_id=b.booking_id "
        "JOIN smart_devices sd ON ac.device_id=sd.device_id "
        "JOIN properties p ON sd.property_id=p.property_id "
        "WHERE b.guest_id=%s AND ac.is_active=1 ORDER BY ac.valid_from DESC",
        (session["user_id"],)
    )
    return render_template("guest/access_codes.html", codes=rows)
