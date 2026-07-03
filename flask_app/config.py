import os

DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 3306,
    "user": "app_admin",
    "password": "Admin#2026!",
    "database": "rental_access_db",
    "autocommit": False,
}

SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-in-production")
