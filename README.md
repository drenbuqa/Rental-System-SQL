# Short-Term Rental & Smart Access Management System

A relational database system built in MySQL covering the full lifecycle of a short-term rental platform — from property listings and bookings to guest identity verification, smart lock access codes, and financial reporting. Designed and implemented as a Database Design course project at Modul University Vienna.

---

## Overview

Short-term rental hosts typically manage several disconnected systems: a listing platform, spreadsheets for identity checks, a separate smart-lock app, and chat threads for cleaners. This fragmentation creates real problems — door codes get reused across stays, identity verification is skipped under time pressure, and there is no single audit trail showing who entered a property and when.

This system consolidates the full rental lifecycle into a single relational database with a Python console application for end-to-end interaction.

---

## Database Design

- **46 tables** — 29 transactional, 17 reference
- **Full 3NF normalisation** — reference tables eliminate update anomalies; one deliberate denormalisation in bookings preserves the agreed price at booking time
- **4 user roles** — host, guest, cleaner, admin — each with minimum necessary privileges
- **5 reporting views** — public property catalog, upcoming check-ins dashboard, host revenue summary, security audit log, unverified guest compliance view
- **4 composite indexes** — targeting the most frequent query patterns including availability search by property and date range
- **4 business transactions** — booking creation, booking confirmation with access code generation, cancellation with refund, stay completion with host payout

### Key Design Decisions

- Monetary values use `DECIMAL` not `FLOAT` to avoid floating point rounding in financial records
- `access_events` uses `BIGINT` primary key as the table grows with every lock interaction
- Users modeled as a supertype with `host_profiles` and `guest_profiles` as 1:1 subtypes sharing the user primary key, avoiding a wide table full of nulls
- Booking overlap enforced in the application layer using the interval condition since MySQL has no declarative temporal non-overlap constraint

---

## File Structure

```
Rental-System-SQL/
├── 01_schema.sql                        # All 46 tables with constraints and foreign keys
├── 02_indexes_views_roles_transactions.sql  # Indexes, views, roles, and transactions
├── 03_sample_data.sql                   # Coherent sample data across all 46 tables
├── app.py                               # Python console application
├── ER_Diagram.png                       # Entity-Relationship diagram
└── README.md
```

---

## Entity-Relationship Diagram

![ER Diagram](ER_Diagram.png)

---

## Python Console Application

The app exposes 9 operations covering all four CRUD verbs:

- Search available properties by date range and city
- Create a booking (validates capacity and date overlap, then atomically inserts booking + payment + door code)
- Cancel a booking (updates status and deactivates access codes in one transaction)
- List upcoming check-ins
- View guest spending report
- View host revenue summary
- Generate a new access code for a booking
- Purge expired access codes
- View property access audit log

All input is validated before reaching SQL, every statement is parameterised against SQL injection, and database errors are caught and returned as readable messages.

---

## Setup

```bash
# 1. Create the database and run the scripts in order
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_indexes_views_roles_transactions.sql
mysql -u root -p < 03_sample_data.sql

# 2. Install Python dependencies
pip install mysql-connector-python

# 3. Configure your connection in app.py
# Update DB_CONFIG with your host, user, password

# 4. Run the application
python app.py
```

---

## Tech Stack

- **Database:** MySQL 8.0
- **Language:** Python 3
- **Connector:** mysql-connector-python
- **Design tool:** MySQL Workbench (ER diagram)

---

## Key SQL Techniques Used

- Correlated NOT EXISTS subquery for date-overlap availability search
- Correlated subqueries per row in the upcoming check-ins view (verification status, active code count)
- Nested subquery inside HAVING for guest spending report
- Role-based access control with least-privilege principle (host IBAN hidden from public views)
- ACID transactions with explicit ROLLBACK on failure
- Delta Lake-style temporal correctness — booking price preserved at time of creation

---

## Authors

Bora Elshani, Dren Buqa
B.Sc. Applied Data Science — Modul University Vienna
Database Design and Management Course, 2025