/*=====================================================================
  PROJECT: Brazilian E-commerce Analysis
  DELIVERABLE: Data Checks & Consistency (SQL Server)
=====================================================================*/

USE BrazilianEcommerce;
GO


SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
GO

/*---------------------------------------------------------------------
  2. ROW COUNTS: baseline record counts for the audit report.
---------------------------------------------------------------------*/
SELECT 'Customer' AS table_name, COUNT_BIG(*) AS row_count FROM Customer
UNION ALL SELECT 'geolocation', COUNT_BIG(*) FROM geolocation
UNION ALL SELECT 'orders', COUNT_BIG(*) FROM orders
UNION ALL SELECT 'order_items', COUNT_BIG(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT_BIG(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT_BIG(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT_BIG(*) FROM products
UNION ALL SELECT 'product_category_name_translation', COUNT_BIG(*) FROM product_category_name_translation
UNION ALL SELECT 'sellers', COUNT_BIG(*) FROM sellers
ORDER BY table_name;
GO

SELECT 'Customer' AS table_name, 'customer_id' AS column_name, COUNT_BIG(*) AS issue_count
FROM Customer WHERE customer_id IS NULL
UNION ALL SELECT 'Customer','customer_unique_id',COUNT_BIG(*) FROM Customer WHERE customer_unique_id IS NULL
UNION ALL SELECT 'Customer','customer_zip_code_prefix',COUNT_BIG(*) FROM Customer WHERE customer_zip_code_prefix IS NULL
UNION ALL SELECT 'Customer','customer_city',COUNT_BIG(*) FROM Customer WHERE customer_city IS NULL
UNION ALL SELECT 'Customer','customer_state',COUNT_BIG(*) FROM Customer WHERE customer_state IS NULL
UNION ALL SELECT 'orders','order_id',COUNT_BIG(*) FROM orders WHERE order_id IS NULL
UNION ALL SELECT 'orders','customer_id',COUNT_BIG(*) FROM orders WHERE customer_id IS NULL
UNION ALL SELECT 'orders','order_status',COUNT_BIG(*) FROM orders WHERE order_status IS NULL
UNION ALL SELECT 'orders','order_purchase_timestamp',COUNT_BIG(*) FROM orders WHERE order_purchase_timestamp IS NULL
UNION ALL SELECT 'order_items','order_id',COUNT_BIG(*) FROM order_items WHERE order_id IS NULL
UNION ALL SELECT 'order_items','product_id',COUNT_BIG(*) FROM order_items WHERE product_id IS NULL
UNION ALL SELECT 'order_items','seller_id',COUNT_BIG(*) FROM order_items WHERE seller_id IS NULL
UNION ALL SELECT 'order_items','price',COUNT_BIG(*) FROM order_items WHERE price IS NULL
UNION ALL SELECT 'order_items','freight_value',COUNT_BIG(*) FROM order_items WHERE freight_value IS NULL
UNION ALL SELECT 'order_payments','order_id',COUNT_BIG(*) FROM order_payments WHERE order_id IS NULL
UNION ALL SELECT 'order_payments','payment_type',COUNT_BIG(*) FROM order_payments WHERE payment_type IS NULL
UNION ALL SELECT 'order_payments','payment_value',COUNT_BIG(*) FROM order_payments WHERE payment_value IS NULL
UNION ALL SELECT 'order_reviews','review_id',COUNT_BIG(*) FROM order_reviews WHERE review_id IS NULL
UNION ALL SELECT 'order_reviews','order_id',COUNT_BIG(*) FROM order_reviews WHERE order_id IS NULL
UNION ALL SELECT 'order_reviews','review_score',COUNT_BIG(*) FROM order_reviews WHERE review_score IS NULL
UNION ALL SELECT 'products','product_id',COUNT_BIG(*) FROM products WHERE product_id IS NULL
UNION ALL SELECT 'sellers','seller_id',COUNT_BIG(*) FROM sellers WHERE seller_id IS NULL
UNION ALL SELECT 'product_category_name_translation','product_category_name',COUNT_BIG(*) FROM product_category_name_translation WHERE product_category_name IS NULL
ORDER BY table_name, column_name;
GO

SELECT
  SUM(CASE WHEN review_comment_title IS NULL OR LTRIM(RTRIM(review_comment_title)) = '' THEN 1 ELSE 0 END) AS missing_review_titles,
  SUM(CASE WHEN review_comment_message IS NULL OR LTRIM(RTRIM(review_comment_message)) = '' THEN 1 ELSE 0 END) AS missing_review_messages
FROM order_reviews;
GO


-- Customer table: customer_id should normally identify one row.
SELECT customer_id, COUNT_BIG(*) AS occurrences
FROM Customer
GROUP BY customer_id
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;
GO

-- Orders table: order_id should normally identify one row.
SELECT order_id, COUNT_BIG(*) AS occurrences
FROM orders
GROUP BY order_id
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;
GO

-- Order items: check expected order-line key (order_id, order_item_id).
SELECT order_id, order_item_id, COUNT_BIG(*) AS occurrences
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;
GO

-- Payments: check expected payment sequence key within each order.
SELECT order_id, payment_sequential, COUNT_BIG(*) AS occurrences
FROM order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;
GO

-- Product and seller identifiers should normally be unique in their tables.
SELECT product_id, COUNT_BIG(*) AS occurrences FROM products
GROUP BY product_id HAVING COUNT_BIG(*) > 1;
GO
SELECT seller_id, COUNT_BIG(*) AS occurrences FROM sellers
GROUP BY seller_id HAVING COUNT_BIG(*) > 1;
GO

-- Category translation: source category should normally map to one row.
SELECT product_category_name, COUNT_BIG(*) AS occurrences
FROM product_category_name_translation
GROUP BY product_category_name
HAVING COUNT_BIG(*) > 1;
GO


-- Orders whose customer_id does not exist in Customer.
SELECT o.order_id, o.customer_id
FROM orders AS o
LEFT JOIN Customer AS c ON c.customer_id = o.customer_id
WHERE o.customer_id IS NOT NULL AND c.customer_id IS NULL;
GO

-- Order items referencing unknown orders.
SELECT oi.order_id, oi.order_item_id
FROM order_items AS oi
LEFT JOIN orders AS o ON o.order_id = oi.order_id
WHERE oi.order_id IS NOT NULL AND o.order_id IS NULL;
GO

-- Order items referencing unknown products.
SELECT oi.order_id, oi.order_item_id, oi.product_id
FROM order_items AS oi
LEFT JOIN products AS p ON p.product_id = oi.product_id
WHERE oi.product_id IS NOT NULL AND p.product_id IS NULL;
GO

-- Order items referencing unknown sellers.
SELECT oi.order_id, oi.order_item_id, oi.seller_id
FROM order_items AS oi
LEFT JOIN sellers AS s ON s.seller_id = oi.seller_id
WHERE oi.seller_id IS NOT NULL AND s.seller_id IS NULL;
GO

-- Payments referencing unknown orders.
SELECT pay.order_id, pay.payment_sequential
FROM order_payments AS pay
LEFT JOIN orders AS o ON o.order_id = pay.order_id
WHERE pay.order_id IS NOT NULL AND o.order_id IS NULL;
GO

-- Reviews referencing unknown orders.
SELECT r.review_id, r.order_id
FROM order_reviews AS r
LEFT JOIN orders AS o ON o.order_id = r.order_id
WHERE r.order_id IS NOT NULL AND o.order_id IS NULL;
GO

-- Products whose category has no translation mapping (may be valid if category is NULL).
SELECT p.product_id, p.product_category_name
FROM products AS p
LEFT JOIN product_category_name_translation AS t
  ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;
GO


-- Unexpected order statuses: compare with project/business documentation.
SELECT order_status, COUNT_BIG(*) AS occurrences
FROM orders
GROUP BY order_status
ORDER BY occurrences DESC;
GO

-- Negative price or freight values.
SELECT order_id, order_item_id, price, freight_value
FROM order_items
WHERE price < 0 OR freight_value < 0;
GO

-- Negative payment values or non-positive installment counts.
SELECT order_id, payment_sequential, payment_type, payment_installments, payment_value
FROM order_payments
WHERE payment_value < 0 OR payment_installments < 1;
GO

-- Review scores are expected to be from 1 through 5 in this dataset.
SELECT review_id, order_id, review_score
FROM order_reviews
WHERE review_score NOT BETWEEN 1 AND 5;
GO

-- Product dimensions / weight / photo count should not be negative.
SELECT product_id, product_weight_g, product_length_cm, product_height_cm,
       product_width_cm, product_photos_qty
FROM products
WHERE product_weight_g < 0
   OR product_length_cm < 0
   OR product_height_cm < 0
   OR product_width_cm < 0
   OR product_photos_qty < 0;
GO

-- Geographic coordinates must fall within valid global ranges.
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
       geolocation_city, geolocation_state
FROM geolocation
WHERE geolocation_lat NOT BETWEEN -90 AND 90
   OR geolocation_lng NOT BETWEEN -180 AND 180;
GO

-- Blank text values can behave differently from NULL; check key text fields.
SELECT 'Customer' AS table_name, 'customer_city' AS column_name, COUNT_BIG(*) AS blank_count
FROM Customer WHERE customer_city IS NOT NULL AND LTRIM(RTRIM(customer_city)) = ''
UNION ALL
SELECT 'Customer','customer_state',COUNT_BIG(*) FROM Customer WHERE customer_state IS NOT NULL AND LTRIM(RTRIM(customer_state)) = ''
UNION ALL
SELECT 'orders','order_status',COUNT_BIG(*) FROM orders WHERE order_status IS NOT NULL AND LTRIM(RTRIM(order_status)) = ''
UNION ALL
SELECT 'order_payments','payment_type',COUNT_BIG(*) FROM order_payments WHERE payment_type IS NOT NULL AND LTRIM(RTRIM(payment_type)) = ''
ORDER BY table_name, column_name;
GO


-- Dates that occur before the purchase timestamp.
SELECT order_id, order_status, order_purchase_timestamp, order_approved_at,
       order_delivered_carrier_date, order_delivered_customer_date,
       order_estimated_delivery_date
FROM orders
WHERE (order_approved_at IS NOT NULL AND order_approved_at < order_purchase_timestamp)
   OR (order_delivered_carrier_date IS NOT NULL AND order_delivered_carrier_date < order_purchase_timestamp)
   OR (order_delivered_customer_date IS NOT NULL AND order_delivered_customer_date < order_purchase_timestamp);
GO

-- Customer delivery before carrier handoff is a candidate inconsistency.
SELECT order_id, order_delivered_carrier_date, order_delivered_customer_date
FROM orders
WHERE order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date < order_delivered_carrier_date;
GO

-- Compare actual delivery with estimated delivery; this is for late-delivery analysis,
-- not necessarily a data error. Review only delivered orders with both dates present.
SELECT order_id, order_status, order_delivered_customer_date,
       order_estimated_delivery_date,
       DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS days_after_estimate
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL
  AND order_delivered_customer_date > order_estimated_delivery_date
ORDER BY days_after_estimate DESC;
GO

-- Shipping limit before order purchase: inspect if business rules indicate this is invalid.
SELECT oi.order_id, oi.order_item_id, oi.shipping_limit_date,
       o.order_purchase_timestamp
FROM order_items AS oi
JOIN orders AS o ON o.order_id = oi.order_id
WHERE oi.shipping_limit_date IS NOT NULL
  AND o.order_purchase_timestamp IS NOT NULL
  AND oi.shipping_limit_date < o.order_purchase_timestamp;
GO


WITH ItemTotals AS (
    SELECT order_id,
           SUM(COALESCE(price, 0) + COALESCE(freight_value, 0)) AS item_plus_freight_total
    FROM order_items
    GROUP BY order_id
),
PaymentTotals AS (
    SELECT order_id, SUM(COALESCE(payment_value, 0)) AS payment_total
    FROM order_payments
    GROUP BY order_id
)
SELECT COALESCE(i.order_id, p.order_id) AS order_id,
       i.item_plus_freight_total,
       p.payment_total,
       p.payment_total - i.item_plus_freight_total AS difference
FROM ItemTotals AS i
FULL OUTER JOIN PaymentTotals AS p ON p.order_id = i.order_id
WHERE i.order_id IS NULL
   OR p.order_id IS NULL
   OR ABS(COALESCE(p.payment_total, 0) - COALESCE(i.item_plus_freight_total, 0)) > 0.02
ORDER BY order_id;
GO

select * from product_category_name_translation

