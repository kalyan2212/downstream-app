"""
web_app.py
==========
Flask web application for downstream data management.

- Fetches customer records from the upstream REST API.
- Stores / syncs them in a PostgreSQL database.
- Provides a UI to update each customer's Salary and Company fields.
- Persists all edits back to PostgreSQL.

Usage:
    pip install flask requests psycopg2-binary gunicorn
    python web_app.py
    Then open http://localhost:5001 in your browser.

Environment variables (set in .env or system environment):
    DB_HOST      – PostgreSQL host        (default: localhost)
    DB_PORT      – PostgreSQL port        (default: 5432)
    DB_NAME      – Database name          (default: downstream)
    DB_USER      – Database user          (default: downstream_user)
    DB_PASSWORD  – Database password      (required)
    UPSTREAM_URL – Upstream API base URL  (default: http://localhost:5000)
    API_KEY      – Upstream API key       (default: downstream-app-key-002)
"""

import os
import psycopg2
import psycopg2.extras
import requests
from datetime import datetime, timezone
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify

# ─── Configuration ────────────────────────────────────────────────────────────
UPSTREAM_BASE_URL = os.environ.get("UPSTREAM_URL", "http://localhost:5000")
API_KEY           = os.environ.get("API_KEY", "downstream-app-key-002")
BATCH_SIZE        = 100
LAST_RUN_FILE     = os.path.join(os.path.dirname(__file__), "last_run.txt")

HEADERS = {"X-API-Key": API_KEY}
# ──────────────────────────────────────────────────────────────────────────────

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET", "downstream-secret-key-change-me")


# ─── Database helpers ─────────────────────────────────────────────────────────

def get_db():
    """Open and return a new PostgreSQL connection."""
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ.get("DB_NAME", "downstream"),
        user=os.environ.get("DB_USER", "downstream_user"),
        password=os.environ.get("DB_PASSWORD", ""),
    )


def query(sql, params=None, fetch="all"):
    """Execute a SQL statement and optionally return rows as dicts."""
    conn = get_db()
    try:
        with conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql, params or ())
                if fetch == "all":
                    return cur.fetchall()
                if fetch == "one":
                    return cur.fetchone()
                return None
    finally:
        conn.close()


def init_db():
    """Create the downstream table if it does not exist yet."""
    query("""
        CREATE TABLE IF NOT EXISTS customers (
            id          INTEGER PRIMARY KEY,
            first_name  TEXT,
            last_name   TEXT,
            email       TEXT,
            phone       TEXT,
            city        TEXT,
            salary      NUMERIC(12,2) DEFAULT 0,
            company     TEXT          DEFAULT '',
            fetched_at  TEXT,
            updated_at  TEXT
        )
    """, fetch="none")


def load_last_run():
    if os.path.exists(LAST_RUN_FILE):
        with open(LAST_RUN_FILE) as f:
            return f.read().strip() or None
    return None


def save_last_run(ts: str):
    with open(LAST_RUN_FILE, "w") as f:
        f.write(ts)


# ─── Upstream fetch ───────────────────────────────────────────────────────────

def fetch_all_customers(since=None):
    """Pull all (or incremental) customer records from the upstream API."""
    all_records = []
    offset = 0

    while True:
        params = {"limit": BATCH_SIZE, "offset": offset}
        if since:
            params["since"] = since

        resp = requests.get(
            f"{UPSTREAM_BASE_URL}/api/customers",
            params=params,
            headers=HEADERS,
            timeout=10,
        )

        if resp.status_code != 200:
            raise RuntimeError(f"Upstream API returned HTTP {resp.status_code}: {resp.text}")

        payload = resp.json()
        batch   = payload.get("data", [])
        total   = payload.get("total", 0)

        all_records.extend(batch)
        offset += len(batch)

        if offset >= total or len(batch) == 0:
            break

    return all_records


def upsert_customers(records: list, fetched_at: str):
    """
    Insert new customers or update existing ones while preserving
    any salary / company edits the user has already made.
    """
    conn = get_db()
    try:
        with conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                for r in records:
                    cur.execute(
                        "SELECT salary, company FROM customers WHERE id = %s", (r["id"],)
                    )
                    existing = cur.fetchone()

                    if existing:
                        # Update upstream fields only; keep user-edited salary/company
                        cur.execute("""
                            UPDATE customers
                               SET first_name  = %s,
                                   last_name   = %s,
                                   email       = %s,
                                   phone       = %s,
                                   city        = %s,
                                   fetched_at  = %s
                             WHERE id = %s
                        """, (
                            r.get("first_name", ""),
                            r.get("last_name", ""),
                            r.get("email", ""),
                            r.get("phone", ""),
                            r.get("city", ""),
                            fetched_at,
                            r["id"],
                        ))
                    else:
                        cur.execute("""
                            INSERT INTO customers
                                (id, first_name, last_name, email, phone, city,
                                 salary, company, fetched_at, updated_at)
                            VALUES (%s, %s, %s, %s, %s, %s, 0, '', %s, NULL)
                        """, (
                            r["id"],
                            r.get("first_name", ""),
                            r.get("last_name", ""),
                            r.get("email", ""),
                            r.get("phone", ""),
                            r.get("city", ""),
                            fetched_at,
                        ))
    finally:
        conn.close()


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    search = request.args.get("search", "").strip()
    if search:
        like = f"%{search}%"
        rows = query("""
            SELECT * FROM customers
            WHERE first_name ILIKE %s OR last_name ILIKE %s
               OR email ILIKE %s OR city ILIKE %s OR company ILIKE %s
            ORDER BY id
        """, (like, like, like, like, like))
    else:
        rows = query("SELECT * FROM customers ORDER BY id")

    last_run = load_last_run()
    return render_template("index.html", customers=rows or [], last_run=last_run, search=search)


@app.route("/fetch", methods=["POST"])
def fetch():
    """Trigger an incremental (or full) fetch from the upstream API."""
    fetch_mode = request.form.get("mode", "incremental")
    since = load_last_run() if fetch_mode == "incremental" else None
    run_ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    try:
        records = fetch_all_customers(since)
        upsert_customers(records, run_ts)
        save_last_run(run_ts)
        flash(f"Successfully fetched and stored {len(records)} record(s).", "success")
    except Exception as exc:
        flash(f"Fetch failed: {exc}", "danger")

    return redirect(url_for("index"))


@app.route("/edit/<int:customer_id>", methods=["GET", "POST"])
def edit(customer_id):
    """Display and handle the edit form for a single customer."""
    customer = query("SELECT * FROM customers WHERE id = %s", (customer_id,), fetch="one")

    if customer is None:
        flash("Customer not found.", "warning")
        return redirect(url_for("index"))

    if request.method == "POST":
        salary  = request.form.get("salary", "0") or "0"
        company = request.form.get("company", "").strip()
        updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

        try:
            salary = float(salary)
        except ValueError:
            flash("Salary must be a number.", "danger")
            return render_template("edit.html", customer=customer)

        query("""
            UPDATE customers
               SET salary = %s, company = %s, updated_at = %s
             WHERE id = %s
        """, (salary, company, updated_at, customer_id), fetch="none")

        flash(f"Customer #{customer_id} updated successfully.", "success")
        return redirect(url_for("index"))

    return render_template("edit.html", customer=customer)


@app.route("/api/customers", methods=["GET"])
def api_customers():
    """JSON endpoint – returns all downstream customers (for external use)."""
    rows = query("SELECT * FROM customers ORDER BY id") or []
    return jsonify([dict(r) for r in rows])


@app.route("/api/customer/<int:customer_id>", methods=["PUT"])
def api_update_customer(customer_id):
    """JSON endpoint – update salary / company for a single customer."""
    data = request.get_json(force=True) or {}
    salary     = data.get("salary")
    company    = data.get("company")
    updated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

    existing = query("SELECT id FROM customers WHERE id = %s", (customer_id,), fetch="one")
    if not existing:
        return jsonify({"error": "Not found"}), 404

    if salary is not None:
        query("UPDATE customers SET salary = %s, updated_at = %s WHERE id = %s",
              (float(salary), updated_at, customer_id), fetch="none")
    if company is not None:
        query("UPDATE customers SET company = %s, updated_at = %s WHERE id = %s",
              (company, updated_at, customer_id), fetch="none")

    return jsonify({"message": "Updated", "id": customer_id})


# ─── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    init_db()
    print("Downstream web app running at http://localhost:5001")
    app.run(host="0.0.0.0", port=5001, debug=True)
