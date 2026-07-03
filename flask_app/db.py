import mysql.connector
from mysql.connector import Error
from flask import g
from config import DB_CONFIG


def get_db():
    if "db" not in g:
        g.db = mysql.connector.connect(**DB_CONFIG)
    return g.db


def close_db(e=None):
    db = g.pop("db", None)
    if db is not None and db.is_connected():
        db.close()


def query(sql, params=None, fetchone=False, commit=False):
    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute(sql, params or ())
    if commit:
        db.commit()
        return cur.lastrowid
    if fetchone:
        return cur.fetchone()
    return cur.fetchall()


def callproc(name, args):
    """Call a stored procedure; returns (out_args, result_sets)."""
    db = get_db()
    cur = db.cursor()
    result = cur.callproc(name, args)
    rows = []
    for rs in cur.stored_results():
        rows.append(rs.fetchall())
    db.commit()
    return result, rows
