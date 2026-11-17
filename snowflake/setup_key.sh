#!/bin/bash
# One-time setup for Snowflake key-pair authentication.
#
# 1. Creates an RSA key pair. The private key stays on this computer, outside
#    the repo, readable only by you. The public key is the half Snowflake keeps.
# 2. Copies an ALTER USER statement to the clipboard. Paste it into a Snowsight
#    worksheet and run it to attach the public key to your Snowflake user.
#
# Usage:  bash snowflake/setup_key.sh     (fill in SNOWFLAKE_USER in .env first)
set -euo pipefail
cd "$(dirname "$0")/.."

SF_USER=$(grep '^SNOWFLAKE_USER=' .env | cut -d= -f2-)
KEY=$(grep '^SNOWFLAKE_PRIVATE_KEY_FILE=' .env | cut -d= -f2-)
KEY="${KEY/#\~/$HOME}"

if [ -z "$SF_USER" ] || [ "$SF_USER" = "your_username" ]; then
    echo "Open .env and set SNOWFLAKE_USER to your Snowflake username first."
    exit 1
fi

if [ -f "$KEY" ]; then
    echo "Using the existing private key at $KEY"
else
    mkdir -p "$(dirname "$KEY")"
    # 2048-bit RSA key in PKCS#8 format, the format Snowflake expects.
    openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -nocrypt -out "$KEY"
    chmod 600 "$KEY"
    echo "Created a private key at $KEY"
fi

# The public key, without its BEGIN/END lines and line breaks.
PUBLIC_KEY=$(openssl rsa -in "$KEY" -pubout 2>/dev/null | grep -v "PUBLIC KEY" | tr -d '\n')

echo "ALTER USER $SF_USER SET RSA_PUBLIC_KEY='$PUBLIC_KEY';" | pbcopy
echo "Copied an ALTER USER statement to your clipboard."
echo "Paste it into a Snowsight worksheet and run it."
