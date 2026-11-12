-- 00_load.sql
-- Load the raw Olist CSVs into DuckDB tables (one table per file).
-- Types are declared explicitly instead of trusting auto-detection:
--   * zip code prefixes are VARCHAR so leading zeros ('01037') survive
--   * all *_date / *_timestamp columns become TIMESTAMP so date math works

CREATE OR REPLACE TABLE customers AS
SELECT * FROM read_csv('data/olist_customers_dataset.csv', header = true, columns = {
    'customer_id': 'VARCHAR', 'customer_unique_id': 'VARCHAR',
    'customer_zip_code_prefix': 'VARCHAR', 'customer_city': 'VARCHAR', 'customer_state': 'VARCHAR'});

CREATE OR REPLACE TABLE orders AS
SELECT * FROM read_csv('data/olist_orders_dataset.csv', header = true, columns = {
    'order_id': 'VARCHAR', 'customer_id': 'VARCHAR', 'order_status': 'VARCHAR',
    'order_purchase_timestamp': 'TIMESTAMP', 'order_approved_at': 'TIMESTAMP',
    'order_delivered_carrier_date': 'TIMESTAMP', 'order_delivered_customer_date': 'TIMESTAMP',
    'order_estimated_delivery_date': 'TIMESTAMP'});

CREATE OR REPLACE TABLE order_items AS
SELECT * FROM read_csv('data/olist_order_items_dataset.csv', header = true, columns = {
    'order_id': 'VARCHAR', 'order_item_id': 'INTEGER', 'product_id': 'VARCHAR', 'seller_id': 'VARCHAR',
    'shipping_limit_date': 'TIMESTAMP', 'price': 'DECIMAL(10,2)', 'freight_value': 'DECIMAL(10,2)'});

CREATE OR REPLACE TABLE order_payments AS
SELECT * FROM read_csv('data/olist_order_payments_dataset.csv', header = true, columns = {
    'order_id': 'VARCHAR', 'payment_sequential': 'INTEGER', 'payment_type': 'VARCHAR',
    'payment_installments': 'INTEGER', 'payment_value': 'DECIMAL(10,2)'});

CREATE OR REPLACE TABLE order_reviews AS
SELECT * FROM read_csv('data/olist_order_reviews_dataset.csv', header = true, columns = {
    'review_id': 'VARCHAR', 'order_id': 'VARCHAR', 'review_score': 'INTEGER',
    'review_comment_title': 'VARCHAR', 'review_comment_message': 'VARCHAR',
    'review_creation_date': 'TIMESTAMP', 'review_answer_timestamp': 'TIMESTAMP'});

CREATE OR REPLACE TABLE products AS
SELECT * FROM read_csv('data/olist_products_dataset.csv', header = true, columns = {
    'product_id': 'VARCHAR', 'product_category_name': 'VARCHAR',
    'product_name_lenght': 'INTEGER', 'product_description_lenght': 'INTEGER',
    'product_photos_qty': 'INTEGER', 'product_weight_g': 'INTEGER', 'product_length_cm': 'INTEGER',
    'product_height_cm': 'INTEGER', 'product_width_cm': 'INTEGER'});

CREATE OR REPLACE TABLE sellers AS
SELECT * FROM read_csv('data/olist_sellers_dataset.csv', header = true, columns = {
    'seller_id': 'VARCHAR', 'seller_zip_code_prefix': 'VARCHAR',
    'seller_city': 'VARCHAR', 'seller_state': 'VARCHAR'});

CREATE OR REPLACE TABLE category_translation AS
SELECT * FROM read_csv('data/product_category_name_translation.csv', header = true, columns = {
    'product_category_name': 'VARCHAR', 'product_category_name_english': 'VARCHAR'});

CREATE OR REPLACE TABLE geolocation AS
SELECT * FROM read_csv('data/olist_geolocation_dataset.csv', header = true, columns = {
    'geolocation_zip_code_prefix': 'VARCHAR', 'geolocation_lat': 'DOUBLE', 'geolocation_lng': 'DOUBLE',
    'geolocation_city': 'VARCHAR', 'geolocation_state': 'VARCHAR'});
