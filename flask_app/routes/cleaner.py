from flask import Blueprint, render_template, request, redirect, url_for, flash, session
from db import query
from routes.auth import login_required
import mysql.connector

cleaner_bp = Blueprint("cleaner", __name__)


@cleaner_bp.route("/")
@login_required("staff")
def dashboard():
    uid = session["user_id"]
    pending = query(
        "SELECT COUNT(*) AS n FROM cleaning_tasks WHERE assigned_to = %s AND task_status != 'done'",
        (uid,), fetchone=True
    )["n"]
    done_today = query(
        "SELECT COUNT(*) AS n FROM cleaning_tasks "
        "WHERE assigned_to = %s AND task_status = 'done' AND scheduled_date = CURDATE()",
        (uid,), fetchone=True
    )["n"]
    return render_template("cleaner/dashboard.html", pending=pending, done_today=done_today)


@cleaner_bp.route("/tasks")
@login_required("staff")
def tasks():
    uid = session["user_id"]
    rows = query(
        "SELECT ct.task_id, ct.scheduled_date, ct.task_status, ct.notes, "
        "p.title AS property_title, b.check_in_date, b.check_out_date "
        "FROM cleaning_tasks ct "
        "JOIN properties p ON ct.property_id = p.property_id "
        "LEFT JOIN bookings b ON ct.booking_id = b.booking_id "
        "WHERE ct.assigned_to = %s "
        "ORDER BY ct.scheduled_date ASC",
        (uid,)
    )
    return render_template("cleaner/tasks.html", tasks=rows)


@cleaner_bp.route("/tasks/<int:task_id>/done", methods=["POST"])
@login_required("staff")
def mark_done(task_id):
    uid = session["user_id"]
    try:
        query(
            "UPDATE cleaning_tasks SET task_status = 'done' "
            "WHERE task_id = %s AND assigned_to = %s",
            (task_id, uid), commit=True
        )
        flash("Task marked as done.", "success")
    except mysql.connector.Error:
        flash("Could not update task.", "danger")
    return redirect(url_for("cleaner.tasks"))


@cleaner_bp.route("/checkins")
@login_required("staff")
def checkins():
    rows = query("SELECT * FROM v_upcoming_checkins ORDER BY check_in_date ASC LIMIT 50")
    return render_template("cleaner/checkins.html", checkins=rows)


@cleaner_bp.route("/my-codes")
@login_required("staff")
def my_codes():
    uid = session["user_id"]
    rows = query(
        "SELECT ac.code_value, ac.valid_from, ac.valid_until, ac.is_active, "
        "sd.location_label, sd.serial_number, p.title AS property_title "
        "FROM access_codes ac "
        "JOIN smart_devices sd ON ac.device_id = sd.device_id "
        "JOIN properties p ON sd.property_id = p.property_id "
        "WHERE ac.assigned_to = %s ORDER BY ac.valid_from DESC",
        (uid,)
    )
    return render_template("cleaner/my_codes.html", codes=rows)
