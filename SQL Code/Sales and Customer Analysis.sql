
CREATE DATABASE BrazilianEcommerce;
GO

USE BrazilianEcommerce;
GO

------------------------------------------
SELECT
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

-------------------------------------------

SELECT 'Customer' AS table_name, COUNT_BIG(*) AS row_count
FROM dbo.Customer

UNION ALL
SELECT 'orders', COUNT_BIG(*) FROM dbo.orders

UNION ALL
SELECT 'order_items', COUNT_BIG(*) FROM dbo.order_items

UNION ALL
SELECT 'order_payments', COUNT_BIG(*) FROM dbo.order_payments

UNION ALL
SELECT 'order_reviews', COUNT_BIG(*) FROM dbo.order_reviews

UNION ALL
SELECT 'products', COUNT_BIG(*) FROM dbo.products

UNION ALL
SELECT 'sellers', COUNT_BIG(*) FROM dbo.sellers

UNION ALL
SELECT 'geolocation', COUNT_BIG(*) FROM dbo.geolocation

UNION ALL
SELECT 'product_category_name_translation',
       COUNT_BIG(*)
FROM dbo.product_category_name_translation;

---------------------------------------------------------

-- Check missing customer identifiers
SELECT COUNT(*) AS missing_customer_ids
FROM dbo.Customer
WHERE customer_id IS NULL;

-- Check missing customer location information
SELECT
    SUM(CASE WHEN customer_city IS NULL
             THEN 1 ELSE 0 END) AS missing_city,
    SUM(CASE WHEN customer_state IS NULL
             THEN 1 ELSE 0 END) AS missing_state,
    SUM(CASE WHEN customer_zip_code_prefix IS NULL
             THEN 1 ELSE 0 END) AS missing_zip_prefix
FROM dbo.Customer;


-- Check missing values in important order fields
SELECT
    SUM(CASE WHEN order_id IS NULL
             THEN 1 ELSE 0 END) AS missing_order_id,
    SUM(CASE WHEN customer_id IS NULL
             THEN 1 ELSE 0 END) AS missing_customer_id,
    SUM(CASE WHEN order_status IS NULL
             THEN 1 ELSE 0 END) AS missing_order_status,
    SUM(CASE WHEN order_purchase_timestamp IS NULL
             THEN 1 ELSE 0 END) AS missing_purchase_date
FROM dbo.orders;
----------------------------------------------------------


-- 1. Overall sales and order KPIs
SELECT
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS customer_order_records,
    SUM(oi.price) AS total_item_revenue,
    SUM(oi.freight_value) AS total_freight_revenue,
    SUM(oi.price + oi.freight_value) AS total_order_item_value,
    AVG(CAST(oi.price AS DECIMAL(18,2))) AS avg_item_price
FROM dbo.orders AS o
LEFT JOIN dbo.order_items AS oi
    ON o.order_id = oi.order_id;

-- 2. Order status analysis
    SELECT
    order_status,
    COUNT(*) AS total_orders,
    CAST(
        100.0 * COUNT(*) /
        NULLIF(SUM(COUNT(*)) OVER (), 0)
        AS DECIMAL(6,2)
    ) AS percentage_of_orders
FROM dbo.orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- 3.Average order value (AOV)
WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price) AS item_value,
        SUM(freight_value) AS freight_value,
        SUM(price + freight_value) AS order_value
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    COUNT(*) AS orders_with_items,
    AVG(CAST(order_value AS DECIMAL(18,2)))
        AS average_order_value,
    AVG(CAST(item_value AS DECIMAL(18,2)))
        AS average_item_value_per_order,
    AVG(CAST(freight_value AS DECIMAL(18,2)))
        AS average_freight_per_order
FROM OrderTotals;

--4.Identify repeat customers
WITH CustomerOrders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM dbo.Customer AS c
    JOIN dbo.orders AS o
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS unique_customers,
    SUM(CASE WHEN order_count = 1
             THEN 1 ELSE 0 END) AS one_time_customers,
    SUM(CASE WHEN order_count > 1
             THEN 1 ELSE 0 END) AS repeat_customers,
    CAST(
        100.0 * SUM(CASE WHEN order_count > 1
                         THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(6,2)
    ) AS repeat_customer_percentage,
    AVG(CAST(order_count AS DECIMAL(10,2)))
        AS average_orders_per_customer
FROM CustomerOrders;

--5.Top 10 customers by order value
SELECT TOP 10
    c.Customer_unique_id,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.price + oi.freight_value) AS total_order_value
FROM dbo.Customer AS c
JOIN dbo.orders AS o
    ON c.customer_id = o.customer_id
JOIN dbo.order_items AS oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_unique_id
ORDER BY total_order_value DESC;

--6.Seller performance
SELECT TOP 10
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS orders_served,
    COUNT(*) AS items_sold,
    SUM(oi.price) AS item_revenue,
    SUM(oi.price + oi.freight_value) AS total_order_item_value
FROM dbo.sellers AS s
JOIN dbo.order_items AS oi
    ON s.seller_id = oi.seller_id
GROUP BY
    s.seller_id,
    s.seller_state
ORDER BY item_revenue DESC;

