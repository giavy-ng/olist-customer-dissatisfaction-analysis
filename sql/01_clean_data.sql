-- =====================================================================
-- Olist Dissatisfaction Project — Data Cleaning Pipeline (T-SQL)
-- =====================================================================
-- Purpose: Prepare the analytical dataset used throughout the project.
--
-- Pipeline: raw CSV -> staging tables -> clean_reviews -> analysis_orders
--           -> export CSV -> consumed by Python (EDA) and Power BI (model)
-- =====================================================================

CREATE DATABASE olist_dissatisfaction;
GO
USE olist_dissatisfaction;
GO


-- =====================================================================
-- STEP 0 — Create raw staging tables
-- =====================================================================

DROP TABLE IF EXISTS dbo.raw_orders;
CREATE TABLE dbo.raw_orders (
    order_id                        VARCHAR(64) PRIMARY KEY,
    customer_id                     VARCHAR(64) NOT NULL,
    order_status                    VARCHAR(32) NOT NULL,
    order_purchase_timestamp        DATETIME2,
    order_approved_at               DATETIME2,
    order_delivered_carrier_date    DATETIME2,
    order_delivered_customer_date   DATETIME2,
    order_estimated_delivery_date   DATETIME2
);

DROP TABLE IF EXISTS dbo.raw_customers;
CREATE TABLE dbo.raw_customers (
    customer_id                 VARCHAR(64) PRIMARY KEY,
    customer_unique_id           VARCHAR(64) NOT NULL,
    customer_zip_code_prefix      VARCHAR(16),
    customer_city                  VARCHAR(128),
    customer_state                  VARCHAR(8)
);

DROP TABLE IF EXISTS dbo.raw_sellers;
CREATE TABLE dbo.raw_sellers (
    seller_id                 VARCHAR(64) PRIMARY KEY,
    seller_zip_code_prefix      VARCHAR(16),
    seller_city                   VARCHAR(128),
    seller_state                   VARCHAR(8)
);

DROP TABLE IF EXISTS dbo.raw_products;
CREATE TABLE dbo.raw_products (
    product_id                       VARCHAR(64) PRIMARY KEY,
    product_category_name             VARCHAR(128),
    product_name_lenght                 INT,
    product_description_lenght           INT,
    product_photos_qty                    INT,
    product_weight_g                       INT,
    product_length_cm                       INT,
    product_height_cm                        INT,
    product_width_cm                          INT
);

DROP TABLE IF EXISTS dbo.raw_order_items;
CREATE TABLE dbo.raw_order_items (
    order_id             VARCHAR(64) NOT NULL,
    order_item_id          INT NOT NULL,
    product_id             VARCHAR(64) NOT NULL,
    seller_id              VARCHAR(64) NOT NULL,
    shipping_limit_date      DATETIME2,
    price                      DECIMAL(12,2),
    freight_value                DECIMAL(12,2),
    PRIMARY KEY (order_id, order_item_id)
);

DROP TABLE IF EXISTS dbo.raw_order_payments;
CREATE TABLE dbo.raw_order_payments (
    order_id                VARCHAR(64) NOT NULL,
    payment_sequential        INT NOT NULL,
    payment_type                VARCHAR(32),
    payment_installments          INT,
    payment_value                   DECIMAL(12,2),
    PRIMARY KEY (order_id, payment_sequential)
);

DROP TABLE IF EXISTS dbo.raw_order_reviews;
CREATE TABLE dbo.raw_order_reviews (
    review_id                  VARCHAR(64) NOT NULL,
    order_id                    VARCHAR(64) NOT NULL,
    review_score                 SMALLINT,
    review_comment_title           NVARCHAR(256),
    review_comment_message           NVARCHAR(MAX),
    review_creation_date               DATETIME2,
    review_answer_timestamp              DATETIME2
    -- NOTE: No primary key is defined because order_id is not unique in the raw dataset.
    -- Duplicate reviews are resolved in Step 2.
);

DROP TABLE IF EXISTS dbo.raw_category_translation;
CREATE TABLE dbo.raw_category_translation (
    product_category_name            VARCHAR(128) PRIMARY KEY,
    product_category_name_english      VARCHAR(128)
);
GO

-- Import raw CSV files into the staging tables.
BULK INSERT dbo.raw_orders
FROM 'C:\data\olist_orders_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_customers
FROM 'C:\data\olist_customers_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_sellers
FROM 'C:\data\olist_sellers_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_products
FROM 'C:\data\olist_products_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_order_items
FROM 'C:\data\olist_order_items_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_order_payments
FROM 'C:\data\olist_order_payments_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_order_reviews
FROM 'C:\data\olist_order_reviews_dataset.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', FORMAT = 'CSV');
 
BULK INSERT dbo.raw_category_translation
FROM 'C:\data\product_category_name_translation.csv'
WITH (FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', FORMAT = 'CSV');
GO

-- Note:
-- Some Olist CSV files use CRLF line endings (e.g. order_reviews, category_translation).
-- ROWTERMINATOR is adjusted accordingly.


-- =====================================================================
-- STEP 1 — Data quality check: confirm the duplicate-review problem
-- =====================================================================
-- Inspect the raw review table to quantify duplicate review
-- submissions before applying the deduplication rule.

SELECT
    COUNT(*)                              AS raw_review_rows,
    COUNT(DISTINCT order_id)              AS distinct_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id)   AS duplicate_row_count
FROM dbo.raw_order_reviews;
-- Result: 99224 raw rows vs 98673 distinct order_id -> 551 duplicate rows.
-- Cause: some orders received more than one review submission
-- (e.g. buyer updated their review, or  multiple review events were recorded).


-- =====================================================================
-- STEP 2 — Remove duplicates -> clean_reviews
-- =====================================================================
-- Business rule: Retain the latest submitted review for each order.
-- Rationale: The latest review best represents the customer's final sentiment
-- and prevents double-counting a single order.

DROP TABLE IF EXISTS dbo.clean_reviews;

WITH ranked_reviews AS (
    SELECT
        review_id,
        order_id,
        review_score,
        review_creation_date,
        review_answer_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_answer_timestamp DESC, review_id DESC
        ) AS rn
    FROM dbo.raw_order_reviews
)
SELECT review_id, order_id, review_score, review_creation_date, review_answer_timestamp
INTO dbo.clean_reviews
FROM ranked_reviews
WHERE rn = 1;

ALTER TABLE dbo.clean_reviews ADD CONSTRAINT PK_clean_reviews PRIMARY KEY (order_id);

-- Validation: Row count should match the number of distinct order_id values identified in Step 1.
SELECT COUNT(*) AS clean_reviews_rows FROM dbo.clean_reviews;  -- result: 98673 -> match
GO


-- =====================================================================
-- STEP 3 — Create analysis_orders
-- =====================================================================
-- Scope: Sep 2016 - Aug 2018 purchase window (raw data truncates after
-- this — review/delivery coverage collapses in the final two raw
-- months, see notebook 01 for the evidence), delivered orders only
-- (non-delivered statuses have no order_delivered_customer_date and
-- cannot carry a valid delivery-time signal).
--
-- Derived delivery metrics are computed here so downstream
-- analysis uses a single, consistent business definition.

DROP TABLE IF EXISTS dbo.analysis_orders;

SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 1 ELSE 0 END AS is_late,
    DATEDIFF(DAY, o.order_estimated_delivery_date, o.order_delivered_customer_date) AS delay_days,
    cr.review_score,
    CASE WHEN cr.review_score <= 2 THEN 1 ELSE 0 END AS is_negative_review
INTO dbo.analysis_orders
FROM dbo.raw_orders o
LEFT JOIN dbo.clean_reviews cr ON cr.order_id = o.order_id
WHERE o.order_purchase_timestamp >= '2016-09-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
  AND o.order_status = 'delivered';

ALTER TABLE dbo.analysis_orders ADD CONSTRAINT PK_analysis_orders PRIMARY KEY (order_id);

-- Sanity check
SELECT COUNT(*) AS analysis_orders_rows FROM dbo.analysis_orders;  -- result: 96478

-- Known source-data quirk: a small number of orders (~8) are marked as
-- delivered but have a NULL order_delivered_customer_date.
-- Delivery-derived fields therefore remain NULL by design.
-- These orders are retained because they still contain valid review information 
-- and contribute to platform-level dissatisfaction metrics.
-- They are excluded only from delivery-time analyses downstream (see Notebook 02, Section 2).
SELECT COUNT(*) AS delivered_missing_delivery_date
FROM dbo.analysis_orders
WHERE order_delivered_customer_date IS NULL;  -- result: ~8
GO

-- =====================================================================
-- STEP 4 — Referential integrity check (post-clean)
-- =====================================================================
-- Confirm that the cleaned tables do not introduce orphaned keys.

SELECT COUNT(*) AS orphaned_clean_reviews
FROM dbo.clean_reviews cr
LEFT JOIN dbo.raw_orders o ON o.order_id = cr.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS analysis_orders_without_review
FROM dbo.analysis_orders
WHERE review_score IS NULL;
-- Result: 646 delivered orders have no associated review.
-- This is valid because submitting a review is optional; these orders
-- remain in the analytical dataset for delivery-performance analysis,
-- but are excluded from review-based metrics where a review score is required.
GO


-- =====================================================================
-- Pipeline complete.
-- =====================================================================
-- Outputs:
--   • dbo.clean_reviews
--   • dbo.analysis_orders
--
-- These tables serve as the single analytical source for the Python
-- notebooks and the Power BI dashboard.
-- =====================================================================
