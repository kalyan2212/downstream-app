"""
downstream_integration.py
=========================
Example: How the DOWNSTREAM application pulls customer records
FROM the data-entry application via its REST API for further processing.

The script uses incremental polling: it remembers the last time it ran
(stored in last_run.txt) and only fetches records created since then.
This avoids re-processing the entire dataset on every run.

Usage:
    python downstream_integration.py

Requirements:
    pip install requests
"""

import requests
import json
import os
from datetime import datetime, timezone

# ─── Configuration ────────────────────────────────────────────────────────────
BASE_URL      = "http://localhost:5000"
API_KEY       = "downstream-app-key-002"   # must match an entry in app.py API_KEYS
BATCH_SIZE    = 100                         # records per page
LAST_RUN_FILE = os.path.join(os.path.dirname(__file__), "last_run.txt")

HEADERS = {
    "X-API-Key": API_KEY,
}
# ──────────────────────────────────────────────────────────────────────────────


def load_last_run() -> str | None:
    """Return the ISO timestamp of the last successful run, or None."""
    if os.path.exists(LAST_RUN_FILE):
        with open(LAST_RUN_FILE) as f:
            return f.read().strip() or None
    return None


def save_last_run(ts: str):
    """Persist the current run timestamp so the next run can use it."""
    with open(LAST_RUN_FILE, "w") as f:
        f.write(ts)


def fetch_all_new_customers(since: str | None) -> list[dict]:
    """
    Pull every customer record newer than `since` using paginated requests.
    If `since` is None, fetches all records (first-ever run).
    """
    all_records = []
    offset = 0

    while True:
        params = {"limit": BATCH_SIZE, "offset": offset}
        if since:
            params["since"] = since

        response = requests.get(
            f"{BASE_URL}/api/customers",
            params=params,
            headers=HEADERS,
            timeout=10,
        )

        if response.status_code != 200:
            raise RuntimeError(f"HTTP {response.status_code}: {response.text}")

        payload = response.json()
        batch   = payload["data"]
        total   = payload["total"]

        all_records.extend(batch)
        print(f"  Fetched records {offset + 1}–{offset + len(batch)} of {total}")

        offset += len(batch)
        if offset >= total or len(batch) == 0:
            break

    return all_records


def process_customer(customer: dict):
    """
    YOUR downstream processing logic goes here.
    Examples: enrich data, write to a data warehouse, trigger a workflow, etc.
    """
    print(f"  Processing id={customer['id']}  "
          f"{customer['first_name']} {customer['last_name']}  "
          f"city={customer['city']}")
    # TODO: replace with real processing (DB insert, API call, ML pipeline, etc.)


# ─── Main polling loop ────────────────────────────────────────────────────────
if __name__ == "__main__":
    run_started_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    since          = load_last_run()

    if since:
        print(f"Incremental fetch: pulling records created after {since}")
    else:
        print("First run: pulling ALL records")

    try:
        customers = fetch_all_new_customers(since)
        print(f"\nFetched {len(customers)} new record(s). Processing ...\n")

        for customer in customers:
            process_customer(customer)

        # Only update the cursor after all records are processed successfully
        save_last_run(run_started_at)
        print(f"\nDone. Last-run timestamp updated to {run_started_at}")

    except RuntimeError as exc:
        print(f"\n[ERROR] {exc}")
        print("Last-run timestamp NOT updated – next run will retry from the same point.")
