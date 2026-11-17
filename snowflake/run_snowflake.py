"""Run the converted SQL on Snowflake and export every analysis query to snowflake/output/.

The Snowflake twin of run_sql.py. All logic lives in the .sql files; this script only:
  1. runs 01_staging.sql and ab_01_clean.sql (the clean views)
  2. for each analysis file, runs every query that follows a
     '-- @export: <file>.csv' marker and writes it to snowflake/output/<file>.csv
Run load_data.py first.  Usage:  .venv/bin/python snowflake/run_snowflake.py
"""
import csv
import re
from pathlib import Path

from sf_connect import get_connection

SQL = Path(__file__).resolve().parent
OUT = SQL / "output"
OUT.mkdir(exist_ok=True)
marker = re.compile(r"^--\s*@export:\s*(\S+)\s*$", re.M)

with get_connection() as conn:
    for setup in ["01_staging.sql", "ab_01_clean.sql"]:
        for _ in conn.execute_string((SQL / setup).read_text(), remove_comments=True):
            pass
        print(f"ran {setup}")

    cur = conn.cursor()
    files = sorted(SQL.glob("q*.sql")) + [SQL / "99_audit_checks.sql", SQL / "ab_02_summary.sql"]
    for path in files:
        parts = marker.split(path.read_text())
        # parts = [header, name1, sql1, name2, sql2, ...]
        for name, query in zip(parts[1::2], parts[2::2]):
            cur.execute(query.strip().rstrip(";"))
            rows = cur.fetchall()
            # Snowflake returns column names in capitals; lower-case them to match DuckDB's CSVs.
            header = [col[0].lower() for col in cur.description]
            with open(OUT / name, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(header)
                writer.writerows(rows)
            print(f"{path.name:36s} -> snowflake/output/{name:32s} {len(rows):>5} rows")
