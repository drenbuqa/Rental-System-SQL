import logging
from flask import Flask, render_template, request, redirect, url_for, session, flash
from config import SECRET_KEY
from db import get_db, close_db, query
from werkzeug.security import generate_password_hash, check_password_hash
import mysql.connector

log = logging.getLogger("werkzeug")
log.setLevel(logging.ERROR)

app = Flask(__name__)
app.secret_key = SECRET_KEY
app.logger.setLevel(logging.ERROR)
app.teardown_appcontext(close_db)

from routes.admin import admin_bp
from routes.host import host_bp
from routes.guest import guest_bp
from routes.cleaner import cleaner_bp

app.register_blueprint(admin_bp,   url_prefix="/admin")
app.register_blueprint(host_bp,    url_prefix="/host")
app.register_blueprint(guest_bp,   url_prefix="/guest")
app.register_blueprint(cleaner_bp, url_prefix="/cleaner")


@app.route("/", methods=["GET", "POST"])
def login():
    if "user_id" in session:
        return _redirect_by_role(session["role"])

    error = None
    if request.method == "POST":
        email    = request.form.get("email", "").strip()
        password = request.form.get("password", "").strip()
        try:
            user = query(
                "SELECT user_id, email, account_role, password_hash, is_active "
                "FROM users WHERE email=%s",
                (email,), fetchone=True
            )
            if not user:
                error = "Invalid email or password."
            elif not user["is_active"]:
                error = "Your account has been deactivated."
            else:
                stored = user["password_hash"]
                # New accounts use werkzeug pbkdf2 hash; legacy demo accounts use plaintext tokens.
                if stored.startswith("pbkdf2:") or stored.startswith("scrypt:"):
                    ok = check_password_hash(stored, password)
                else:
                    ok = (password == stored)
                if ok:
                    session["user_id"] = user["user_id"]
                    session["email"]   = user["email"]
                    session["role"]    = user["account_role"]
                    return _redirect_by_role(user["account_role"])
                else:
                    error = "Invalid email or password."
        except mysql.connector.Error:
            error = "Database error — please try again."

    return render_template("login.html", error=error)


@app.route("/register", methods=["GET", "POST"])
def register():
    if "user_id" in session:
        return _redirect_by_role(session["role"])

    error = None
    if request.method == "POST":
        first_name = request.form.get("first_name", "").strip()
        last_name  = request.form.get("last_name", "").strip()
        email      = request.form.get("email", "").strip().lower()
        password   = request.form.get("password", "")
        confirm    = request.form.get("confirm_password", "")

        if not all([first_name, last_name, email, password]):
            error = "All fields are required."
        elif len(password) < 8:
            error = "Password must be at least 8 characters."
        elif password != confirm:
            error = "Passwords do not match."
        else:
            try:
                existing = query("SELECT user_id FROM users WHERE email=%s", (email,), fetchone=True)
                if existing:
                    error = "An account with this email already exists."
                else:
                    pw_hash = generate_password_hash(password)
                    query(
                        "INSERT INTO users (email, password_hash, first_name, last_name, account_role, is_active) "
                        "VALUES (%s, %s, %s, %s, 'guest', 1)",
                        (email, pw_hash, first_name, last_name), commit=True
                    )
                    new_user = query("SELECT user_id FROM users WHERE email=%s", (email,), fetchone=True)
                    query(
                        "INSERT INTO guest_profiles (guest_id) VALUES (%s)",
                        (new_user["user_id"],), commit=True
                    )
                    session["user_id"] = new_user["user_id"]
                    session["email"]   = email
                    session["role"]    = "guest"
                    flash("Welcome to RentalAccess! Your account has been created.", "success")
                    return redirect(url_for("guest.dashboard"))
            except mysql.connector.Error as e:
                error = f"Registration failed: {e}"

    return render_template("register.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.route("/become-host", methods=["GET", "POST"])
def become_host():
    from routes.auth import login_required as _lr
    if "user_id" not in session:
        return redirect(url_for("login"))
    if session.get("role") == "host":
        return redirect(url_for("host.dashboard"))

    error = None
    if request.method == "POST":
        company = request.form.get("company_name", "").strip() or None
        iban    = request.form.get("payout_iban", "").strip() or None
        try:
            query(
                "UPDATE users SET account_role='host' WHERE user_id=%s",
                (session["user_id"],), commit=True
            )
            query(
                "INSERT INTO host_profiles (host_id, company_name, payout_iban, joined_date) "
                "VALUES (%s, %s, %s, CURDATE())",
                (session["user_id"], company, iban), commit=True
            )
            session["role"] = "host"
            flash("Welcome as a Host! You can now list your first property.", "success")
            return redirect(url_for("host.add_property"))
        except mysql.connector.Error as e:
            error = str(e)

    return render_template("become_host.html", error=error)


def _redirect_by_role(role):
    dest = {"admin": "admin.dashboard", "host": "host.dashboard",
            "guest": "guest.dashboard", "staff": "cleaner.dashboard"}
    return redirect(url_for(dest.get(role, "login")))


if __name__ == "__main__":
    app.run(debug=False, port=5050, use_reloader=False)
