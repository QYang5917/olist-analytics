"""Run every statement in one SQL file on Snowflake and print each result status.

Usage:  .venv/bin/python snowflake/run_file.py snowflake/00_setup.sql
"""
import sys
from pathlib import Path

from sf_connect import get_connection

path = Path(sys.argv[1])
# use_context=False: the setup file creates the warehouse and database itself.
with get_connection(use_context=False) as conn:
    # execute_string splits the file on semicolons and runs the statements in order.
    for cur in conn.execute_string(path.read_text(), remove_comments=True):
        first_line = " ".join(cur.query.split())[:60]
        print(f"{first_line:<62} -> {cur.fetchone()[0]}")
