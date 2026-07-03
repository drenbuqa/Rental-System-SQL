from functools import wraps
from flask import session, redirect, url_for


def login_required(*roles):
    """Decorator: require login and optional role membership."""
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            if "user_id" not in session:
                return redirect(url_for("login"))
            if roles and session.get("role") not in roles:
                return redirect(url_for("login"))
            return f(*args, **kwargs)
        return wrapper
    return decorator
