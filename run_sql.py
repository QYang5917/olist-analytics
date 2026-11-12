"""Build olist.duckdb from data/ and export every analysis query to output/.

All analysis logic lives in sql/*.sql. This script only:
  1. runs 00_load.sql and 01_staging.sql (tables + clean views)
  2. for each q*.sql file, runs every query that follows a
     '-- @export: <file>.csv' marker and writes it to output/<file>.csv
Usage:  python run_sql.py
"""
import re
from pathlib import Path

import duckdb

ROOT = Path(__file__).parent
SQL, OUT = ROOT / "sql", ROOT / "output"
OUT.mkdir(exist_ok=True)

con = duckdb.connect(str(ROOT / "olist.duckdb"))
for setup in ["00_load.sql", "01_staging.sql"]:
    con.execute((SQL / setup).read_text())
    print(f"ran {setup}")

marker = re.compile(r"^--\s*@export:\s*(\S+)\s*$", re.M)
for path in sorted(SQL.glob("q*.sql")) + [SQL / "99_audit_checks.sql"]:
    parts = marker.split(path.read_text())
    # parts = [header, name1, sql1, name2, sql2, ...]
    for name, query in zip(parts[1::2], parts[2::2]):
        query = query.strip().rstrip(";")
        rel = con.sql(query)
        rel.write_csv(str(OUT / name))
        print(f"{path.name:36s} -> output/{name:32s} {len(rel.fetchall()):>5} rows")
