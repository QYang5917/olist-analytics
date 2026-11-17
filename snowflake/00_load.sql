-- 00_load.sql (Snowflake version of sql/00_load.sql)
-- Creates the 9 raw Olist tables and the A/B test table in OLIST.RAW, plus the
-- two helper objects Snowflake uses for loading files: a FILE FORMAT and a STAGE.
-- The upload itself (PUT + COPY INTO) is done by snowflake/load_data.py,
-- because PUT reads a file from your computer and only works from a client.
--
-- Same table names, column names and types as the DuckDB version:
--   * zip code prefixes are VARCHAR so leading zeros ('01037') survive
--   * all *_date / *_timestamp columns are TIMESTAMP_NTZ so date math works
--     (TIMESTAMP_NTZ = "no time zone", the same meaning as DuckDB's TIMESTAMP)

-- How to read the CSVs: a header row, optional double quotes around values
-- (review comments contain commas and line breaks), and empty values as NULL.
CREATE OR REPLACE FILE FORMAT olist_csv
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('')
    ESCAPE_UNENCLOSED_FIELD = NONE;     -- treat a backslash as an ordinary character

-- A stage is a landing area inside Snowflake for uploaded files.
CREATE OR REPLACE STAGE olist_stage FILE_FORMAT = olist_csv;

CREATE OR REPLACE TABLE customers (
    customer_id              VARCHAR,
    customer_unique_id       VARCHAR,
    customer_zip_code_prefix VARCHAR,
    customer_city            VARCHAR,
    customer_state           VARCHAR
);

CREATE OR REPLACE TABLE orders (
    order_id                      VARCHAR,
    customer_id                   VARCHAR,
    order_status                  VARCHAR,
    order_purchase_timestamp      TIMESTAMP_NTZ,
    order_approved_at             TIMESTAMP_NTZ,
    order_delivered_carrier_date  TIMESTAMP_NTZ,
    order_delivered_customer_date TIMESTAMP_NTZ,
    order_estimated_delivery_date TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE order_items (
    order_id            VARCHAR,
    order_item_id       INTEGER,
    product_id          VARCHAR,
    seller_id           VARCHAR,
    shipping_limit_date TIMESTAMP_NTZ,
    price               NUMBER(10,2),
    freight_value       NUMBER(10,2)
);

CREATE OR REPLACE TABLE order_payments (
    order_id             VARCHAR,
    payment_sequential   INTEGER,
    payment_type         VARCHAR,
    payment_installments INTEGER,
    payment_value        NUMBER(10,2)
);

CREATE OR REPLACE TABLE order_reviews (
    review_id               VARCHAR,
    order_id                VARCHAR,
    review_score            INTEGER,
    review_comment_title    VARCHAR,
    review_comment_message  VARCHAR,
    review_creation_date    TIMESTAMP_NTZ,
    review_answer_timestamp TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE products (
    product_id                 VARCHAR,
    product_category_name      VARCHAR,
    product_name_lenght        INTEGER,
    product_description_lenght INTEGER,
    product_photos_qty         INTEGER,
    product_weight_g           INTEGER,
    product_length_cm          INTEGER,
    product_height_cm          INTEGER,
    product_width_cm           INTEGER
);

CREATE OR REPLACE TABLE sellers (
    seller_id              VARCHAR,
    seller_zip_code_prefix VARCHAR,
    seller_city            VARCHAR,
    seller_state           VARCHAR
);

CREATE OR REPLACE TABLE category_translation (
    product_category_name         VARCHAR,
    product_category_name_english VARCHAR
);

CREATE OR REPLACE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR,
    geolocation_lat             DOUBLE,
    geolocation_lng             DOUBLE,
    geolocation_city            VARCHAR,
    geolocation_state           VARCHAR
);

-- A/B test data (data/ab_data.csv). The DuckDB version creates this table at
-- the top of sql/ab_01_clean.sql with read_csv().
-- "GROUP" is a reserved word, so it needs double quotes, and quoted names are
-- case-sensitive in Snowflake. Capitals match how unquoted names are stored.
CREATE OR REPLACE TABLE ab_raw (
    user_id      BIGINT,
    "TIMESTAMP"  TIMESTAMP_NTZ,
    "GROUP"      VARCHAR,
    landing_page VARCHAR,
    converted    INTEGER
);
