-- One-time Snowflake setup: a warehouse (compute) and a database + schema (storage).
-- Run with:  .venv/bin/python snowflake/run_file.py snowflake/00_setup.sql

-- SYSADMIN is the role meant for creating warehouses and databases.
-- ACCOUNTADMIN can do it too, but it is best kept for account-level admin work.
USE ROLE SYSADMIN;

-- A warehouse is the compute that runs queries; it is billed per second while running.
--   XSMALL                the smallest size: 1 credit per hour
--   AUTO_SUSPEND = 60     switch off after 60 idle seconds, so idle time costs nothing
--   AUTO_RESUME = TRUE    switch back on automatically when the next query arrives
--   INITIALLY_SUSPENDED   don't start (or bill) until the first query
CREATE WAREHOUSE IF NOT EXISTS OLIST_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Olist analytics portfolio project';

-- A database holds schemas; a schema holds tables and views.
-- RAW is where the 9 CSVs land, untouched.
CREATE DATABASE IF NOT EXISTS OLIST COMMENT = 'Olist e-commerce analytics';
CREATE SCHEMA IF NOT EXISTS OLIST.RAW COMMENT = 'Olist CSVs loaded as-is';
