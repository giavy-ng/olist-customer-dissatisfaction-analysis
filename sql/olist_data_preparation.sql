-- Create database and raw tables
CREATE DATABASE olist_ecommerce;
GO

USE olist_ecommerce;
GO

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
    customer_id                     VARCHAR(64) PRIMARY KEY,
    customer_unique_id              VARCHAR(64) NOT NULL,
    customer_zip_code_prefix        VARCHAR(16),
    customer_city                   VARCHAR(128),
    customer_state                  VARCHAR(8)
);

DROP TABLE IF EXISTS dbo.raw_sellers;
CREATE TABLE dbo.raw_sellers (
    seller_id                       VARCHAR(64) PRIMARY KEY,
    seller_zip_code_prefix          VARCHAR(16),
    seller_city                     VARCHAR(128),
    seller_state                    VARCHAR(8)
);

DROP TABLE IF EXISTS dbo.raw_products;
CREATE TABLE dbo.raw_products (
    product_id                      VARCHAR(64) PRIMARY KEY,
    product_category_name           VARCHAR(128),
    product_name_lenght             INT,
    product_description_lenght      INT,
    product_photos_qty              INT,
    product_weight_g                INT,
    product_length_cm               INT,
    product_height_cm               INT,
    product_width_cm                INT
);

DROP TABLE IF EXISTS dbo.raw_order_items;
CREATE TABLE dbo.raw_order_items (
    order_id                        VARCHAR(64) NOT NULL,
    order_item_id                   INT NOT NULL,
    product_id                      VARCHAR(64) NOT NULL,
    seller_id                       VARCHAR(64) NOT NULL,
    shipping_limit_date             DATETIME2,
    price                           DECIMAL(12,2),
    freight_value                   DECIMAL(12,2),
    PRIMARY KEY (order_id, order_item_id)
);

DROP TABLE IF EXISTS dbo.raw_order_payments;
CREATE TABLE dbo.raw_order_payments (
    order_id                        VARCHAR(64) NOT NULL,
    payment_sequential              INT NOT NULL,
    payment_type                    VARCHAR(32),
    payment_installments            INT,
    payment_value                   DECIMAL(12,2),
    PRIMARY KEY (order_id, payment_sequential)
);

DROP TABLE IF EXISTS dbo.raw_order_reviews;
CREATE TABLE dbo.raw_order_reviews (
    review_id                       VARCHAR(64) NOT NULL,
    order_id                        VARCHAR(64) NOT NULL,
    review_score                    SMALLINT,
    review_comment_title            NVARCHAR(256),
    review_comment_message          NVARCHAR(MAX),
    review_creation_date            DATETIME2,
    review_answer_timestamp         DATETIME2
);

DROP TABLE IF EXISTS dbo.raw_category_translation;
CREATE TABLE dbo.raw_category_translation (
    product_category_name           VARCHAR(128) PRIMARY KEY,
    product_category_name_english   VARCHAR(128)
);
GO

-- Import raw data
DECLARE @data_path NVARCHAR(400) = N'D:\Olist\data\'

DECLARE @manifest TABLE (target SYSNAME, file_name NVARCHAR(200), row_term VARCHAR(8))
INSERT INTO @manifest (target, file_name, row_term) VALUES
    ('raw_orders',              'olist_orders_dataset.csv',              '0x0a'),
    ('raw_customers',           'olist_customers_dataset.csv',           '0x0a'),
    ('raw_sellers',             'olist_sellers_dataset.csv',             '0x0a'),
    ('raw_products',            'olist_products_dataset.csv',            '0x0a'),
    ('raw_order_items',         'olist_order_items_dataset.csv',         '0x0a'),
    ('raw_order_payments',      'olist_order_payments_dataset.csv',      '0x0a'),
    ('raw_order_reviews',       'olist_order_reviews_dataset.csv',       '0x0d0a'),
    ('raw_category_translation','product_category_name_translation.csv', '0x0d0a')

DECLARE @sql NVARCHAR(MAX)

SELECT @sql = STRING_AGG(CAST(
        'BULK INSERT dbo.' + target
      + ' FROM ''' + @data_path + file_name + ''''
      + ' WITH (FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''' + row_term + ''','
      + '       FORMAT = ''CSV'', CODEPAGE = ''65001'', TABLOCK);'
    AS NVARCHAR(MAX)), CHAR(13) + CHAR(10))
FROM @manifest

EXEC sp_executesql @sql;
GO

-- Validate imported row counts
SELECT 'raw_orders'               AS table_name, COUNT(*) AS rows_loaded, 99441  AS rows_expected FROM dbo.raw_orders
UNION ALL SELECT 'raw_customers',            COUNT(*),  99441  FROM dbo.raw_customers
UNION ALL SELECT 'raw_sellers',              COUNT(*),   3095  FROM dbo.raw_sellers
UNION ALL SELECT 'raw_products',             COUNT(*),  32951  FROM dbo.raw_products
UNION ALL SELECT 'raw_order_items',          COUNT(*), 112650  FROM dbo.raw_order_items
UNION ALL SELECT 'raw_order_payments',       COUNT(*), 103886  FROM dbo.raw_order_payments
UNION ALL SELECT 'raw_order_reviews',        COUNT(*),  99224  FROM dbo.raw_order_reviews
UNION ALL SELECT 'raw_category_translation', COUNT(*),     71  FROM dbo.raw_category_translation;
GO


-- Create analytical dimensions
DROP TABLE IF EXISTS dbo.dim_customers;
SELECT
    customer_id,
    customer_unique_id,                                   -- the true customer grain
    customer_zip_code_prefix,
    LOWER(LTRIM(RTRIM(customer_city))) AS customer_city,
    UPPER(LTRIM(RTRIM(customer_state))) AS customer_state
INTO dbo.dim_customers
FROM dbo.raw_customers;

ALTER TABLE dbo.dim_customers ADD CONSTRAINT PK_dim_customers PRIMARY KEY (customer_id);
CREATE INDEX IX_dim_customers_unique_id ON dbo.dim_customers (customer_unique_id);
GO


DROP TABLE IF EXISTS dbo.dim_sellers;
SELECT
    seller_id,
    seller_zip_code_prefix,
    LOWER(LTRIM(RTRIM(seller_city))) AS seller_city,
    UPPER(LTRIM(RTRIM(seller_state))) AS seller_state
INTO dbo.dim_sellers
FROM dbo.raw_sellers;

ALTER TABLE dbo.dim_sellers ADD CONSTRAINT PK_dim_sellers PRIMARY KEY (seller_id);
GO


DROP TABLE IF EXISTS dbo.dim_products;
SELECT
    p.product_id,
    p.product_category_name,
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'unknown') AS product_category_name_english,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
INTO dbo.dim_products
FROM dbo.raw_products p
LEFT JOIN dbo.raw_category_translation t
       ON t.product_category_name = p.product_category_name;

ALTER TABLE dbo.dim_products ALTER COLUMN product_category_name_english VARCHAR(128) NOT NULL;
ALTER TABLE dbo.dim_products ADD CONSTRAINT PK_dim_products PRIMARY KEY (product_id);
GO


-- Prepare order-level review data
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
GO

-- Create order-level fact table
DROP TABLE IF EXISTS dbo.fct_orders;

-- Scope is the purchase window only. Every order status is kept so that the
-- Power BI model can report Delivery Rate and Order Cancellation Rate, which
-- need the non-delivered orders to exist. Analyses that are about the delivered
-- population filter on is_delivered instead of relying on rows being absent.
WITH scoped_orders AS (
    SELECT *
    FROM dbo.raw_orders
    WHERE order_purchase_timestamp >= '2016-09-01'
      AND order_purchase_timestamp <  '2018-09-01'
),
order_totals AS (
    SELECT
        order_id,
        COUNT(*)                    AS n_items,
        COUNT(DISTINCT seller_id)   AS n_sellers,
        COUNT(DISTINCT product_id)  AS n_products,
        SUM(price)                  AS order_value,
        SUM(freight_value)          AS freight_value
    FROM dbo.raw_order_items
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END AS is_delivered,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    /* delivery time */
    DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                  CAST(o.order_delivered_customer_date AS DATE)) AS delivery_days,

    /* lateness */
    DATEDIFF(DAY, CAST(o.order_estimated_delivery_date AS DATE),
                  CAST(o.order_delivered_customer_date AS DATE)) AS delay_days,
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN CAST(o.order_delivered_customer_date AS DATE)
           > CAST(o.order_estimated_delivery_date AS DATE) THEN 1
        ELSE 0
    END AS is_late,

    /* delivery bucket */
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <=  7 THEN '0-7 days'
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 14 THEN '8-14 days'
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 21 THEN '15-21 days'
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 25 THEN '22-25 days'
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 35 THEN '26-35 days'
        ELSE '36+ days'
    END AS delivery_bucket,
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <=  7 THEN 1
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 14 THEN 2
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 21 THEN 3
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 25 THEN 4
        WHEN DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATE),
                           CAST(o.order_delivered_customer_date AS DATE)) <= 35 THEN 5
        ELSE 6
    END AS delivery_bucket_order,

    /* review */
    CASE WHEN cr.review_score IS NULL THEN 0 ELSE 1 END AS has_review,
    cr.review_score,
    CASE
        WHEN cr.review_score IS NULL THEN NULL      -- unreviewed <> satisfied
        WHEN cr.review_score <= 2 THEN 1
        ELSE 0
    END AS is_negative_review,

    /* order economics */
    it.n_items,
    it.n_sellers,
    it.n_products,
    it.order_value,
    it.freight_value
INTO dbo.fct_orders
FROM scoped_orders o
LEFT JOIN dbo.clean_reviews cr ON cr.order_id = o.order_id
LEFT JOIN dbo.dim_customers c  ON c.customer_id = o.customer_id
LEFT JOIN order_totals it      ON it.order_id = o.order_id;

ALTER TABLE dbo.fct_orders ADD CONSTRAINT PK_fct_orders PRIMARY KEY (order_id);
CREATE INDEX IX_fct_orders_customer ON dbo.fct_orders (customer_id);
GO


-- 07. Create order-seller fact table
DROP TABLE IF EXISTS dbo.fct_order_seller;
SELECT
    oi.order_id,
    oi.seller_id,
    COUNT(*)   AS n_items,
    SUM(oi.price) AS seller_order_value,
    MAX(f.review_score)       AS review_score,        
    MAX(f.is_negative_review) AS is_negative_review,
    MAX(f.delivery_days)      AS delivery_days,
    MAX(f.is_late)            AS is_late
INTO dbo.fct_order_seller
FROM dbo.raw_order_items oi
JOIN dbo.fct_orders f ON f.order_id = oi.order_id
WHERE f.is_delivered = 1          -- seller quality is judged on delivered orders
GROUP BY oi.order_id, oi.seller_id;

ALTER TABLE dbo.fct_order_seller
    ADD CONSTRAINT PK_fct_order_seller PRIMARY KEY (order_id, seller_id);
GO


-- Create order-category fact table
DROP TABLE IF EXISTS dbo.fct_order_category;
SELECT
    oi.order_id,
    p.product_category_name_english AS product_category,
    COUNT(*)      AS n_items,
    SUM(oi.price) AS category_order_value,
    MAX(f.review_score)       AS review_score,
    MAX(f.is_negative_review) AS is_negative_review
INTO dbo.fct_order_category
FROM dbo.raw_order_items oi
JOIN dbo.fct_orders f   ON f.order_id = oi.order_id
JOIN dbo.dim_products p ON p.product_id = oi.product_id
WHERE f.is_delivered = 1          -- category quality is judged on delivered orders
GROUP BY oi.order_id, p.product_category_name_english;

ALTER TABLE dbo.fct_order_category ALTER COLUMN product_category VARCHAR(128) NOT NULL;
ALTER TABLE dbo.fct_order_category
    ADD CONSTRAINT PK_fct_order_category PRIMARY KEY (order_id, product_category);
GO


-- Create review fact table
-- One row per order, already deduplicated in clean_reviews. Keeping reviews as
-- their own table preserves the review-level slicers in the report, and at this
-- grain DISTINCTCOUNT(OrderID) becomes a plain row count.
DROP TABLE IF EXISTS dbo.fct_reviews;

SELECT
    cr.review_id,
    cr.order_id,
    cr.review_score,
    cr.review_creation_date,
    cr.review_answer_timestamp
INTO dbo.fct_reviews
FROM dbo.clean_reviews cr
JOIN dbo.fct_orders f ON f.order_id = cr.order_id;

ALTER TABLE dbo.fct_reviews ADD CONSTRAINT PK_fct_reviews PRIMARY KEY (order_id);
GO


-- Create line-item fact table
-- Kept at raw line-item grain: the Power BI model needs it as the bridge from
-- orders to products and sellers, and it carries price and freight.
DROP TABLE IF EXISTS dbo.fct_order_items;

SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value
INTO dbo.fct_order_items
FROM dbo.raw_order_items oi
JOIN dbo.fct_orders f ON f.order_id = oi.order_id;

ALTER TABLE dbo.fct_order_items
    ADD CONSTRAINT PK_fct_order_items PRIMARY KEY (order_id, order_item_id);
GO


-- Create product category dimension
-- Its own table so the Power BI model can slice by category without going
-- through dim_products, and so untranslated categories stay visible.
DROP TABLE IF EXISTS dbo.dim_product_category;

SELECT
    p.product_category_name,
    MAX(p.product_category_name_english) AS product_category_name_english
INTO dbo.dim_product_category
FROM dbo.dim_products p
WHERE p.product_category_name IS NOT NULL
GROUP BY p.product_category_name;

ALTER TABLE dbo.dim_product_category
    ALTER COLUMN product_category_name VARCHAR(128) NOT NULL;
ALTER TABLE dbo.dim_product_category
    ADD CONSTRAINT PK_dim_product_category PRIMARY KEY (product_category_name);
GO


-- QUALITY CHECKS

-- Validate analytical tables
WITH checks AS (
    /* ---- grain & uniqueness ---------------------------------------------- */
    SELECT 'clean_reviews is one row per order' AS check_name,
           CAST(COUNT(*) - COUNT(DISTINCT order_id) AS BIGINT) AS actual,
           CAST(0 AS BIGINT) AS expected
    FROM dbo.clean_reviews

    UNION ALL
    SELECT 'raw duplicate review submissions removed',
           (SELECT COUNT(*) FROM dbo.raw_order_reviews)
         - (SELECT COUNT(*) FROM dbo.clean_reviews), 551

    UNION ALL
    SELECT 'fct_orders is one row per order',
           COUNT(*) - COUNT(DISTINCT order_id), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'fct_order_seller is one row per order x seller',
           COUNT(*) - COUNT(DISTINCT CONCAT(order_id, '|', seller_id)), 0
    FROM dbo.fct_order_seller

    /* ---- analytical scope ------------------------------------------------- */
    UNION ALL
    SELECT 'fct_orders row count (all statuses)', COUNT(*), 99421 FROM dbo.fct_orders

    UNION ALL
    SELECT 'fct_orders delivered subset',
           SUM(is_delivered), 96478
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'is_delivered agrees with order_status',
           SUM(CASE WHEN is_delivered <> CASE WHEN order_status = 'delivered' THEN 1 ELSE 0 END
                    THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'fct_orders purchases inside the scope window',
           SUM(CASE WHEN order_purchase_timestamp <  '2016-09-01'
                      OR order_purchase_timestamp >= '2018-09-01' THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    /* ---- referential integrity -------------------------------------------- */
    UNION ALL
    SELECT 'fct_orders -> dim_customers unresolved',
           SUM(CASE WHEN c.customer_id IS NULL THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders f LEFT JOIN dbo.dim_customers c ON c.customer_id = f.customer_id

    UNION ALL
    SELECT 'fct_order_seller -> dim_sellers unresolved',
           SUM(CASE WHEN s.seller_id IS NULL THEN 1 ELSE 0 END), 0
    FROM dbo.fct_order_seller fs LEFT JOIN dbo.dim_sellers s ON s.seller_id = fs.seller_id

    UNION ALL
    SELECT 'fct_order_seller -> fct_orders unresolved',
           SUM(CASE WHEN f.order_id IS NULL THEN 1 ELSE 0 END), 0
    FROM dbo.fct_order_seller fs LEFT JOIN dbo.fct_orders f ON f.order_id = fs.order_id

    UNION ALL
    SELECT 'dim_products has no unresolved category',
           SUM(CASE WHEN product_category_name_english IS NULL THEN 1 ELSE 0 END), 0
    FROM dbo.dim_products

    UNION ALL
    SELECT 'fct_order_category covers every delivered order with items',
           (SELECT COUNT(*) FROM dbo.fct_orders f
             WHERE f.is_delivered = 1 AND f.n_items IS NOT NULL)
         - (SELECT COUNT(DISTINCT order_id) FROM dbo.fct_order_category), 0

    /* ---- business rules ---------------------------------------------------- */
    UNION ALL
    SELECT 'is_negative_review is NULL exactly when there is no review',
           SUM(CASE WHEN (review_score IS     NULL AND is_negative_review IS NOT NULL)
                      OR (review_score IS NOT NULL AND is_negative_review IS     NULL)
                    THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'orders without a review (reviewing is optional)',
           SUM(CASE WHEN has_review = 0 THEN 1 ELSE 0 END), 767
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'delivered orders with no delivery date on record',
           SUM(CASE WHEN is_delivered = 1 AND order_delivered_customer_date IS NULL
                    THEN 1 ELSE 0 END), 8
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'delivery metrics NULL only when the delivery date is missing',
           SUM(CASE WHEN (order_delivered_customer_date IS     NULL AND delivery_days IS NOT NULL)
                      OR (order_delivered_customer_date IS NOT NULL AND delivery_days IS     NULL)
                    THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'is_late agrees with delay_days',
           SUM(CASE WHEN is_late <> CASE WHEN delay_days > 0 THEN 1 ELSE 0 END
                    THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders
    WHERE order_delivered_customer_date IS NOT NULL

    UNION ALL
    SELECT 'delivery bucket present whenever the order was delivered on record',
           SUM(CASE WHEN is_delivered = 1 AND order_delivered_customer_date IS NOT NULL
                         AND delivery_bucket IS NULL THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    /* ---- value ranges ------------------------------------------------------ */
    UNION ALL
    SELECT 'no negative or zero order value',
           SUM(CASE WHEN order_value <= 0 THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'orders with no line items (unavailable / cancelled)',
           SUM(CASE WHEN n_items IS NULL THEN 1 ELSE 0 END), 756
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'every delivered order has line items',
           SUM(CASE WHEN is_delivered = 1 AND n_items IS NULL THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'fct_order_items row count', (SELECT COUNT(*) FROM dbo.fct_order_items), 112649

    UNION ALL
    SELECT 'dim_product_category row count', (SELECT COUNT(*) FROM dbo.dim_product_category), 73

    UNION ALL
    SELECT 'no negative delivery time',
           SUM(CASE WHEN delivery_days < 0 THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders

    UNION ALL
    SELECT 'review scores within 1..5',
           SUM(CASE WHEN review_score NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END), 0
    FROM dbo.fct_orders
    WHERE review_score IS NOT NULL
)
SELECT
    check_name,
    actual,
    expected,
    CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY CASE WHEN actual = expected THEN 1 ELSE 0 END, check_name;
GO

-- Validate headline metrics
SELECT
    COUNT(*)                                                  AS orders,
    SUM(has_review)                                           AS reviewed_orders,
    CAST(AVG(CAST(is_negative_review AS FLOAT)) * 100 AS DECIMAL(5,2)) AS dissatisfaction_pct,
    CAST(AVG(CAST(is_late AS FLOAT))            * 100 AS DECIMAL(5,2)) AS late_delivery_pct,
    CAST(AVG(CAST(delivery_days AS FLOAT))            AS DECIMAL(5,2)) AS avg_delivery_days
FROM dbo.fct_orders;
GO
