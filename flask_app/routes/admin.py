from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from db import query
from routes.auth import login_required
import mysql.connector

admin_bp = Blueprint("admin", __name__)


@admin_bp.route("/")
@login_required("admin")
def dashboard():
    stats = {}
    stats["total_users"]      = query("SELECT COUNT(*) AS n FROM users", fetchone=True)["n"]
    stats["active_bookings"]  = query(
        "SELECT COUNT(*) AS n FROM bookings b "
        "JOIN booking_statuses bs ON b.status_id = bs.status_id "
        "WHERE bs.status_name IN ('confirmed','pending')", fetchone=True)["n"]
    stats["total_revenue"]    = query(
        "SELECT COALESCE(SUM(amount),0) AS n FROM payments "
        "WHERE status_id = (SELECT status_id FROM payment_statuses WHERE status_name='captured')",
        fetchone=True)["n"]
    stats["unverified_count"] = query(
        "SELECT COUNT(*) AS n FROM v_unverified_upcoming_guests", fetchone=True)["n"]
    return render_template("admin/dashboard.html", stats=stats)


@admin_bp.route("/analytics")
@login_required("admin")
def analytics():
    kpi = {}
    kpi["total_revenue"] = query(
        "SELECT COALESCE(SUM(amount),0) AS n FROM payments "
        "WHERE status_id=(SELECT status_id FROM payment_statuses WHERE status_name='captured')",
        fetchone=True)["n"]
    kpi["total_bookings"] = query("SELECT COUNT(*) AS n FROM bookings", fetchone=True)["n"]
    kpi["avg_booking_value"] = query(
        "SELECT COALESCE(AVG(total_amount),0) AS n FROM bookings", fetchone=True)["n"]
    kpi["active_properties"] = query(
        "SELECT COUNT(*) AS n FROM properties WHERE is_active=1", fetchone=True)["n"]

    # Monthly revenue (last 12 months)
    monthly = query(
        "SELECT DATE_FORMAT(paid_at,'%b %Y') AS month, "
        "       YEAR(paid_at)*100+MONTH(paid_at) AS sort_key, "
        "       SUM(amount) AS revenue "
        "FROM payments "
        "WHERE status_id=(SELECT status_id FROM payment_statuses WHERE status_name='captured') "
        "  AND paid_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH) "
        "GROUP BY month, sort_key ORDER BY sort_key"
    )
    revenue_months = [r["month"] for r in monthly]
    revenue_values = [float(r["revenue"] or 0) for r in monthly]

    # Bookings by status
    status_counts = query(
        "SELECT bs.status_name, COUNT(*) AS cnt "
        "FROM bookings b JOIN booking_statuses bs ON b.status_id=bs.status_id "
        "GROUP BY bs.status_name ORDER BY cnt DESC"
    )
    status_labels = [r["status_name"] for r in status_counts]
    status_values = [r["cnt"] for r in status_counts]

    # Top properties
    top_properties = query(
        "SELECT * FROM v_property_performance ORDER BY total_revenue DESC LIMIT 8"
    )

    # Above-average spending guests (subquery)
    top_guests = query(
        "SELECT u.user_id, CONCAT(u.first_name,' ',u.last_name) AS guest_name, u.email, "
        "       COUNT(b.booking_id) AS num_bookings, SUM(b.total_amount) AS total_spent "
        "FROM users u "
        "JOIN bookings b ON b.guest_id = u.user_id "
        "WHERE u.account_role = 'guest' "
        "GROUP BY u.user_id, u.first_name, u.last_name, u.email "
        "HAVING SUM(b.total_amount) > (SELECT AVG(total_amount) FROM bookings) "
        "ORDER BY total_spent DESC LIMIT 10"
    )

    return render_template("admin/analytics.html",
        kpi=kpi,
        revenue_months=revenue_months, revenue_values=revenue_values,
        status_counts=status_counts, status_labels=status_labels, status_values=status_values,
        top_properties=top_properties, top_guests=top_guests)


@admin_bp.route("/users")
@login_required("admin")
def users():
    rows = query(
        "SELECT user_id, email, account_role, is_active, created_at "
        "FROM users ORDER BY created_at DESC"
    )
    return render_template("admin/users.html", users=rows)


@admin_bp.route("/users/<int:user_id>/toggle", methods=["POST"])
@login_required("admin")
def toggle_user(user_id):
    try:
        query("UPDATE users SET is_active = NOT is_active WHERE user_id = %s",
              (user_id,), commit=True)
        flash("User status updated.", "success")
    except mysql.connector.Error:
        flash("Could not update user.", "danger")
    return redirect(url_for("admin.users"))


@admin_bp.route("/bookings")
@login_required("admin")
def bookings():
    status_filter = request.args.get("status", "all")
    if status_filter == "all":
        rows = query(
            "SELECT b.booking_id, u.email AS guest_email, p.title AS property_title, "
            "b.check_in_date, b.check_out_date, b.total_amount, bs.status_name, b.booked_at "
            "FROM bookings b "
            "JOIN users u ON b.guest_id=u.user_id "
            "JOIN properties p ON b.property_id=p.property_id "
            "JOIN booking_statuses bs ON b.status_id=bs.status_id "
            "ORDER BY b.booked_at DESC LIMIT 200"
        )
    else:
        rows = query(
            "SELECT b.booking_id, u.email AS guest_email, p.title AS property_title, "
            "b.check_in_date, b.check_out_date, b.total_amount, bs.status_name, b.booked_at "
            "FROM bookings b "
            "JOIN users u ON b.guest_id=u.user_id "
            "JOIN properties p ON b.property_id=p.property_id "
            "JOIN booking_statuses bs ON b.status_id=bs.status_id "
            "WHERE bs.status_name=%s ORDER BY b.booked_at DESC LIMIT 200",
            (status_filter,)
        )
    statuses = [r["status_name"] for r in query("SELECT status_name FROM booking_statuses")]
    return render_template("admin/bookings.html",
                           bookings=rows, statuses=statuses, current_status=status_filter)


@admin_bp.route("/access-audit")
@login_required("admin")
def access_audit():
    rows = query("SELECT * FROM v_access_audit ORDER BY event_time DESC LIMIT 300")
    return render_template("admin/access_audit.html", events=rows)


@admin_bp.route("/unverified-guests")
@login_required("admin")
def unverified_guests():
    rows = query(
        "SELECT * FROM v_unverified_upcoming_guests ORDER BY days_until_checkin ASC"
    )
    pending_verifs = query(
        "SELECT gv.verification_id, gv.guest_id, gv.status, gv.submitted_at, "
        "       CONCAT(u.first_name,' ',u.last_name) AS guest_name, u.email "
        "FROM guest_verifications gv "
        "JOIN users u ON gv.guest_id = u.user_id "
        "WHERE gv.status = 'pending' ORDER BY gv.submitted_at ASC"
    )
    return render_template("admin/unverified_guests.html", guests=rows, pending_verifs=pending_verifs)


@admin_bp.route("/verify-guest/<int:verification_id>", methods=["POST"])
@login_required("admin")
def verify_guest(verification_id):
    action = request.form.get("action")
    reason = request.form.get("rejection_reason", "").strip()
    if action not in ("approved", "rejected"):
        flash("Invalid action.", "warning")
        return redirect(url_for("admin.unverified_guests"))
    try:
        query(
            "UPDATE guest_verifications SET status=%s, reviewed_at=NOW(), reviewed_by=%s "
            + ("" if action == "approved" else ", rejection_reason=%s ") +
            "WHERE verification_id=%s",
            (action, session["user_id"], reason, verification_id) if action == "rejected"
            else (action, session["user_id"], verification_id),
            commit=True
        )
        flash(f"Verification {action}.", "success" if action == "approved" else "warning")
    except mysql.connector.Error as e:
        flash(f"Error: {e}", "danger")
    return redirect(url_for("admin.unverified_guests"))
