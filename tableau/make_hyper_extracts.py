"""Convert the dashboard CSVs into Tableau extract (.hyper) files.

Tableau Public only opens and publishes workbooks whose data is an extract,
so the workbooks in this folder read these .hyper files, not the CSVs.

Reads   tableau/lift_by_segment.csv, conversion_by_segment.csv, daily_conversion.csv
Writes  the same names with a .hyper extension

Run this after make_tableau_data.py whenever the CSVs change.
Usage:  python tableau/make_hyper_extracts.py     (needs: pip install tableauhyperapi)
"""
from pathlib import Path

import pandas as pd
from tableauhyperapi import (Connection, CreateMode, HyperProcess, Inserter, Nullability,
                             SqlType, TableDefinition, TableName, Telemetry)

FOLDER = Path(__file__).resolve().parent
FILES = ["lift_by_segment", "conversion_by_segment", "daily_conversion"]

# Tableau expects an extract's data in a table called "Extract"."Extract".
TABLE = TableName("Extract", "Extract")


def hyper_type(series):
    """Pick the .hyper column type that matches a pandas column."""
    if pd.api.types.is_datetime64_any_dtype(series):
        return SqlType.date()
    if pd.api.types.is_integer_dtype(series):
        return SqlType.big_int()
    if pd.api.types.is_float_dtype(series):
        return SqlType.double()
    return SqlType.text()


# log_config="" stops the Hyper engine from writing a hyperd.log file.
with HyperProcess(telemetry=Telemetry.DO_NOT_SEND_USAGE_DATA_TO_TABLEAU,
                  parameters={"log_config": ""}) as hyper:
    for name in FILES:
        df = pd.read_csv(FOLDER / f"{name}.csv")
        if "date" in df.columns:
            df["date"] = pd.to_datetime(df["date"])

        # One .hyper column per CSV column, same name and order.
        columns = [
            TableDefinition.Column(
                col, hyper_type(df[col]), Nullability.NULLABLE,
                collation="en_US" if hyper_type(df[col]) == SqlType.text() else None,
            )
            for col in df.columns
        ]
        table = TableDefinition(TABLE, columns)

        path = FOLDER / f"{name}.hyper"
        with Connection(hyper.endpoint, str(path), CreateMode.CREATE_AND_REPLACE) as conn:
            conn.catalog.create_schema("Extract")
            conn.catalog.create_table(table)
            with Inserter(conn, table) as inserter:
                for row in df.itertuples(index=False):
                    inserter.add_row([v.date() if isinstance(v, pd.Timestamp) else v for v in row])
                inserter.execute()
            rows = conn.execute_scalar_query(f"SELECT COUNT(*) FROM {TABLE}")

        # Check: the extract has exactly the CSV's rows and columns.
        assert rows == len(df), (name, rows, len(df))
        print(f"tableau/{name}.hyper  {rows:>4} rows  {len(df.columns)} columns")
