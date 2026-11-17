"""Load the 9 Olist CSVs and the A/B test CSV from data/ into OLIST.RAW and check the row counts.

Steps, for each table:
  1. PUT        upload the CSV from this computer to the stage (gzip-compressed)
  2. COPY INTO  parse the staged file into the table, using the olist_csv format
  3. check      Snowflake's row count must equal the number of records in the CSV

Usage:  .venv/bin/python snowflake/load_data.py
"""
import csv
import os
import sys
from pathlib import Path

from sf_connect import get_connection

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)  # so the PUT paths below (data/...) resolve
csv.field_size_limit(sys.maxsize)  # some review comments are long

# table name -> CSV file (same table names as the DuckDB version)
TABLES = {
    "customers": "olist_customers_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "ab_raw": "ab_data.csv",  # A/B test data, used by ab_01_clean.sql
}


def csv_record_count(path):
    """Count data records with a real CSV parser (review comments span several
    lines, so counting lines would overcount). The header is not counted."""
    with open(path, newline="", encoding="utf-8-sig") as f:
        return sum(1 for _ in csv.reader(f)) - 1


with get_connection() as conn:
    cur = conn.cursor()

    # Create the file format, the stage and the empty tables.
    for _ in conn.execute_string((ROOT / "snowflake" / "00_load.sql").read_text(), remove_comments=True):
        pass
    print(f"ran snowflake/00_load.sql (file format, stage, {len(TABLES)} tables)\n")

    print(f"{'table':<22}{'CSV records':>12}{'Snowflake rows':>16}   result")
    all_match = True
    for table, filename in TABLES.items():
        # 1. Upload. AUTO_COMPRESS gzips the file on the way up.
        cur.execute(f"PUT file://data/{filename} @olist_stage AUTO_COMPRESS = TRUE OVERWRITE = TRUE")

        # 2. Load. ON_ERROR = ABORT_STATEMENT: one bad row fails the whole load,
        #    so nothing is skipped silently. PURGE removes the staged file afterwards.
        cur.execute(f"""
            COPY INTO {table}
            FROM @olist_stage/{filename}.gz
            ON_ERROR = ABORT_STATEMENT
            PURGE = TRUE""")

        # 3. Check.
        in_csv = csv_record_count(ROOT / "data" / filename)
        in_snowflake = cur.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        match = in_csv == in_snowflake
        all_match = all_match and match
        print(f"{table:<22}{in_csv:>12,}{in_snowflake:>16,}   {'MATCH' if match else 'MISMATCH'}")

    # Confirm the date/time columns are real timestamps, not text.
    cur.execute("""
        SELECT table_name, column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = 'RAW' AND (column_name LIKE '%DATE%' OR column_name LIKE '%TIMESTAMP%'
                                        OR column_name LIKE '%APPROVED_AT%')
        ORDER BY table_name, ordinal_position""")
    print("\ndate/time columns:")
    for table, column, data_type in cur.fetchall():
        print(f"  {table:<16}{column:<32}{data_type}")

    if not all_match:
        raise SystemExit("\nRow counts do not match. Investigate before going on.")
    print(f"\nAll {len(TABLES)} tables match their CSVs.")
