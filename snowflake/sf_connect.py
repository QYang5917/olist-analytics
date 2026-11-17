"""Open a Snowflake connection using the settings in .env.

Authentication is key-pair: the script proves who it is with a private key
file on this computer, and Snowflake checks it against the public key stored
on the user. No password is stored or typed anywhere.

Test it:  .venv/bin/python snowflake/sf_connect.py
"""
import os
from pathlib import Path

import snowflake.connector

ROOT = Path(__file__).resolve().parent.parent


def load_env(path=ROOT / ".env"):
    """Read KEY=VALUE lines from .env into a dict, skipping comments and blanks."""
    if not path.exists():
        raise SystemExit("No .env file found. Copy .env.example to .env and fill it in.")
    settings = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            settings[key.strip()] = value.strip()
    return settings


def get_connection(use_context=True):
    """Connect to Snowflake.

    use_context=True also selects the role, warehouse, database and schema from
    .env. Pass False before those objects exist (for the first test and setup).
    """
    env = load_env()
    params = {
        "account": env["SNOWFLAKE_ACCOUNT"],
        "user": env["SNOWFLAKE_USER"],
        "authenticator": "SNOWFLAKE_JWT",  # key-pair authentication
        "private_key_file": os.path.expanduser(env["SNOWFLAKE_PRIVATE_KEY_FILE"]),
        # Log out as soon as the script finishes (also silences a connector warning).
        "enable_server_session_keep_alive_auto_detection": False,
    }
    if env.get("SNOWFLAKE_ROLE"):
        params["role"] = env["SNOWFLAKE_ROLE"]
    if use_context:
        for key in ("warehouse", "database", "schema"):
            value = env.get(f"SNOWFLAKE_{key.upper()}")
            if value:
                params[key] = value
    return snowflake.connector.connect(**params)


if __name__ == "__main__":
    # Connection test. These functions need no warehouse, so they cost nothing.
    with get_connection(use_context=False) as conn:
        cur = conn.cursor()
        cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_REGION(), CURRENT_VERSION()")
        user, role, region, version = cur.fetchone()
        print("Connected to Snowflake.")
        print(f"  role     {role}")
        print(f"  region   {region}")
        print(f"  version  {version}")
        cur.execute("SELECT CURRENT_AVAILABLE_ROLES()")
        print(f"  roles    {cur.fetchone()[0]}")
