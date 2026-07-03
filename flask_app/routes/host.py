from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from db import query, callproc
from routes.auth import login_required
import mysql.connector
import random, string

host_bp = Blueprint("host", __name__)


def _host_id():
    # host_id is the same as user_id (host_profiles.host_id references users.user_id)
    return session["user_id"]


@host_bp.route("/")
@login_required("host")
def dashboard():
    host_id = _host_id()
    row = query(
        "SELECT total_properties, total_bookings, gross_revenue, pending_payout "
        "FROM v_host_revenue WHERE host_id = %s",
        (host_id,), fetchone=True
    )
    stats = row or {}
    return render_template("host/dashboard.html", stats=stats)


@host_bp.route("/properties")
@login_required("host")
def properties():
    host_id = _host_id()
    rows = query(
        "SELECT p.property_id, p.title, p.base_price_night, p.cleaning_fee, p.is_active, "
        "       p.bedrooms, p.bathrooms, p.max_guests, p.created_at, "
        "       c.city_name, pt.type_name AS property_type, "
        "       COALESCE(vpp.total_bookings,0) AS total_bookings, "
        "       COALESCE(vpp.total_revenue,0) AS total_revenue, "
        "       vpp.avg_rating, COALESCE(vpp.review_count,0) AS review_count "
        "FROM properties p "
        "JOIN cities c ON p.city_id = c.city_id "
        "JOIN property_types pt ON p.property_type_id = pt.property_type_id "
        "LEFT JOIN v_property_performance vpp ON vpp.title = p.title "
        "WHERE p.host_id = %s ORDER BY p.created_at DESC",
        (host_id,)
    )
    # Amenities per property
    if rows:
        prop_ids = [r["property_id"] for r in rows]
        placeholders = ",".join(["%s"] * len(prop_ids))
        amen_rows = query(
            f"SELECT pa.property_id, a.amenity_name FROM property_amenities pa "
            f"JOIN amenities a ON pa.amenity_id=a.amenity_id "
            f"WHERE pa.property_id IN ({placeholders})",
            tuple(prop_ids)
        )
        amenities_map = {}
        for a in amen_rows:
            amenities_map.setdefault(a["property_id"], []).append(a["amenity_name"])
        # Cover photos
        photo_rows = query(
            f"SELECT property_id, file_url FROM property_photos "
            f"WHERE property_id IN ({placeholders}) AND is_cover=1",
            tuple(prop_ids)
        )
        photos_map = {p["property_id"]: p["file_url"] for p in photo_rows}
    else:
        amenities_map, photos_map = {}, {}

    return render_template("host/properties.html", properties=rows,
                           amenities_map=amenities_map, photos_map=photos_map)


@host_bp.route("/checkins")
@login_required("host")
def checkins():
    host_id = _host_id()
    rows = query(
        "SELECT v.* FROM v_upcoming_checkins v "
        "JOIN properties p ON p.title = v.property_title "
        "WHERE p.host_id = %s "
        "ORDER BY v.check_in_date ASC",
        (host_id,)
    )
    return render_template("host/checkins.html", checkins=rows)


@host_bp.route("/revenue")
@login_required("host")
def revenue():
    row = query("SELECT * FROM v_host_revenue WHERE host_id = %s", (_host_id(),), fetchone=True)
    return render_template("host/revenue.html", revenue=row)


@host_bp.route("/confirm-booking", methods=["GET", "POST"])
@login_required("host")
def confirm_booking():
    if request.method == "POST":
        booking_id = request.form.get("booking_id", "").strip()
        device_id  = request.form.get("device_id", "").strip()
        if not (booking_id and device_id):
            flash("Please select a booking and device.", "warning")
        else:
            try:
                code_value = "".join(random.choices(string.digits, k=6))
                args = (int(booking_id), int(device_id), code_value, None)
                out, _ = callproc("sp_confirm_booking", args)
                flash(out[3] or "Booking confirmed.", "success")
            except (mysql.connector.Error, ValueError) as e:
                flash(f"Error: {e}", "danger")
    devices = query("SELECT device_id, serial_number, location_label FROM smart_devices WHERE is_online = 1")
    pending = query(
        "SELECT b.booking_id, p.title, b.check_in_date, b.check_out_date "
        "FROM bookings b JOIN properties p ON b.property_id = p.property_id "
        "JOIN booking_statuses bs ON b.status_id = bs.status_id "
        "WHERE bs.status_name = 'pending' ORDER BY b.check_in_date"
    )
    return render_template("host/confirm_booking.html", devices=devices, pending=pending)


@host_bp.route("/maintenance", methods=["GET", "POST"])
@login_required("host")
def maintenance():
    host_id = _host_id()
    if request.method == "POST":
        property_id  = request.form.get("property_id")
        category_id  = request.form.get("category_id")
        title        = request.form.get("title", "").strip()
        description  = request.form.get("description", "").strip()
        if not (property_id and category_id and title and description):
            flash("All fields are required.", "warning")
        else:
            try:
                query(
                    "INSERT INTO maintenance_requests "
                    "(property_id, category_id, reported_by, title, description, request_status) "
                    "VALUES (%s, %s, %s, %s, %s, 'open')",
                    (property_id, category_id, session["user_id"], title, description), commit=True
                )
                flash("Maintenance request submitted.", "success")
            except mysql.connector.Error as e:
                flash(f"Error: {e}", "danger")

    props = query("SELECT property_id, title FROM properties WHERE host_id = %s", (host_id,))
    cats  = query("SELECT category_id, category_name FROM maintenance_categories")
    my_requests = query(
        "SELECT mr.request_id, p.title, mc.category_name, mr.description, "
        "mr.request_status, mr.reported_at AS created_at "
        "FROM maintenance_requests mr "
        "JOIN properties p ON mr.property_id = p.property_id "
        "JOIN maintenance_categories mc ON mr.category_id = mc.category_id "
        "WHERE p.host_id = %s ORDER BY mr.reported_at DESC",
        (host_id,)
    )
    return render_template("host/maintenance.html", props=props, cats=cats, requests=my_requests)


@host_bp.route("/properties/add", methods=["GET", "POST"])
@login_required("host")
def add_property():
    prop_types   = query("SELECT property_type_id, type_name FROM property_types ORDER BY type_name")
    cities       = query("SELECT city_id, city_name, country_id FROM cities ORDER BY city_name")
    policies     = query("SELECT policy_id, policy_name, description FROM cancellation_policies ORDER BY policy_id")
    amenities    = query("SELECT amenity_id, amenity_name, category FROM amenities ORDER BY category, amenity_name")
    currencies   = query("SELECT currency_id, currency_code FROM currencies ORDER BY currency_code")

    if request.method == "POST":
        try:
            host_id  = _host_id()
            title    = request.form["title"].strip()
            desc     = request.form.get("description", "").strip() or None
            ptype    = int(request.form["property_type_id"])
            city     = int(request.form["city_id"])
            currency = int(request.form.get("currency_id", 1))
            policy   = int(request.form["cancellation_policy_id"])
            address  = request.form.get("street_address", "").strip() or "N/A"
            bedrooms = int(request.form.get("bedrooms", 1))
            bathrooms= int(request.form.get("bathrooms", 1))
            max_g    = int(request.form.get("max_guests", 2))
            price    = float(request.form["base_price_night"])
            cleaning = float(request.form.get("cleaning_fee", 0) or 0)

            if not title or price <= 0:
                flash("Title and a valid nightly price are required.", "warning")
                return render_template("host/add_property.html", prop_types=prop_types,
                    cities=cities, policies=policies, amenities=amenities, currencies=currencies)

            query(
                "INSERT INTO properties (host_id, property_type_id, city_id, currency_id, "
                "cancellation_policy_id, title, description, street_address, max_guests, "
                "bedrooms, bathrooms, base_price_night, cleaning_fee, is_active) "
                "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,1)",
                (host_id, ptype, city, currency, policy, title, desc, address,
                 max_g, bedrooms, bathrooms, price, cleaning), commit=True
            )
            new_prop = query("SELECT property_id FROM properties WHERE host_id=%s ORDER BY property_id DESC LIMIT 1",
                             (host_id,), fetchone=True)
            prop_id = new_prop["property_id"]

            # Amenities
            amenity_ids = request.form.getlist("amenities")
            for aid in amenity_ids:
                try:
                    query("INSERT IGNORE INTO property_amenities (property_id, amenity_id) VALUES (%s,%s)",
                          (prop_id, int(aid)), commit=True)
                except mysql.connector.Error:
                    pass

            # Photos
            for i in range(1, 6):
                url = request.form.get(f"photo_url_{i}", "").strip()
                caption = request.form.get(f"photo_caption_{i}", "").strip() or None
                if url:
                    is_cover = 1 if i == 1 else 0
                    query(
                        "INSERT INTO property_photos (property_id, file_url, caption, sort_order, is_cover) "
                        "VALUES (%s,%s,%s,%s,%s)",
                        (prop_id, url, caption, i, is_cover), commit=True
                    )

            flash(f'Property "{title}" listed successfully!', "success")
            return redirect(url_for("host.properties"))

        except (mysql.connector.Error, ValueError, KeyError) as e:
            flash(f"Could not create property: {e}", "danger")

    return render_template("host/add_property.html", prop_types=prop_types,
        cities=cities, policies=policies, amenities=amenities, currencies=currencies)


@host_bp.route("/reviews")
@login_required("host")
def reviews():
    host_id = _host_id()
    rows = query(
        "SELECT r.review_id, r.overall_rating, r.comment, r.created_at, r.is_visible, "
        "       p.title AS property_title, "
        "       CONCAT(u.first_name,' ',u.last_name) AS guest_name, "
        "       b.check_in_date, b.check_out_date "
        "FROM reviews r "
        "JOIN bookings b ON r.booking_id = b.booking_id "
        "JOIN properties p ON b.property_id = p.property_id "
        "JOIN users u ON r.author_guest_id = u.user_id "
        "WHERE p.host_id = %s ORDER BY r.created_at DESC",
        (host_id,)
    )
    scores_raw = query(
        "SELECT rs.review_id, rc.category_name, rs.score "
        "FROM review_scores rs "
        "JOIN review_categories rc ON rs.category_id = rc.category_id "
        "WHERE rs.review_id IN ("
        "  SELECT r.review_id FROM reviews r "
        "  JOIN bookings b ON r.booking_id=b.booking_id "
        "  JOIN properties p ON b.property_id=p.property_id "
        "  WHERE p.host_id=%s"
        ")",
        (host_id,)
    )
    scores_map = {}
    for s in scores_raw:
        scores_map.setdefault(s["review_id"], {})[s["category_name"]] = s["score"]

    responses = query(
        "SELECT review_id FROM review_responses WHERE host_id=%s", (host_id,)
    )
    responded_ids = {r["review_id"] for r in responses}

    return render_template("host/reviews.html",
                           reviews=rows, scores_map=scores_map, responded_ids=responded_ids)


@host_bp.route("/reviews/<int:review_id>/respond", methods=["POST"])
@login_required("host")
def respond_review(review_id):
    text = request.form.get("response_text", "").strip()
    if not text:
        flash("Response cannot be empty.", "warning")
        return redirect(url_for("host.reviews"))
    try:
        query(
            "INSERT INTO review_responses (review_id, host_id, response_text, responded_at) "
            "VALUES (%s, %s, %s, NOW())",
            (review_id, _host_id(), text), commit=True
        )
        flash("Response posted.", "success")
    except mysql.connector.Error as e:
        flash(f"Error: {e}", "danger")
    return redirect(url_for("host.reviews"))
