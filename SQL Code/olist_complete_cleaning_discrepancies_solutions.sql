
SET NOCOUNT ON;

-------------------------------------------------------------------------------
-- 0. ROW COUNTS FOR ALL NINE TABLES
-------------------------------------------------------------------------------
SELECT 'Customer' AS table_name, COUNT_BIG(*) AS row_count FROM dbo.Customer
UNION ALL SELECT 'orders', COUNT_BIG(*) FROM dbo.orders
UNION ALL SELECT 'order_items', COUNT_BIG(*) FROM dbo.order_items
UNION ALL SELECT 'order_payments', COUNT_BIG(*) FROM dbo.order_payments
UNION ALL SELECT 'order_reviews', COUNT_BIG(*) FROM dbo.order_reviews
UNION ALL SELECT 'products', COUNT_BIG(*) FROM dbo.products
UNION ALL SELECT 'sellers', COUNT_BIG(*) FROM dbo.sellers
UNION ALL SELECT 'geolocation', COUNT_BIG(*) FROM dbo.geolocation
UNION ALL SELECT 'product_category_name_translation',
                 COUNT_BIG(*) FROM dbo.product_category_name_translation
ORDER BY table_name;

-------------------------------------------------------------------------------
-- 1. DATA PROFILING: NULLS / COMPLETENESS
-- Solution: recover from authoritative source if possible; otherwise preserve
-- NULL and document it. Do not fabricate timestamps, ratings or prices.
-------------------------------------------------------------------------------
SELECT
  COUNT_BIG(*) AS total_orders,
  SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS null_order_id,
  SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
  SUM(CASE WHEN order_status IS NULL THEN 1 ELSE 0 END) AS null_status,
  SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_time,
  SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS null_approval_time,
  SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS null_carrier_time,
  SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_customer_delivery_time
FROM dbo.orders;

SELECT
  COUNT_BIG(*) AS total_products,
  SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS missing_category,
  SUM(CASE WHEN product_name_lenght IS NULL THEN 1 ELSE 0 END) AS missing_name_length,
  SUM(CASE WHEN product_description_lenght IS NULL THEN 1 ELSE 0 END) AS missing_description_length,
  SUM(CASE WHEN product_photos_qty IS NULL THEN 1 ELSE 0 END) AS missing_photo_count,
  SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END) AS missing_weight,
  SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END) AS missing_length,
  SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END) AS missing_height,
  SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END) AS missing_width
FROM dbo.products;

SELECT
  COUNT_BIG(*) AS total_reviews,
  SUM(CASE WHEN review_comment_title IS NULL OR LTRIM(RTRIM(review_comment_title)) = '' THEN 1 ELSE 0 END) AS missing_or_blank_titles,
  SUM(CASE WHEN review_comment_message IS NULL OR LTRIM(RTRIM(review_comment_message)) = '' THEN 1 ELSE 0 END) AS missing_or_blank_messages
FROM dbo.order_reviews;

SELECT
  COUNT_BIG(*) AS total_customers,
  SUM(CASE WHEN customer_city IS NULL OR LTRIM(RTRIM(customer_city)) = '' THEN 1 ELSE 0 END) AS missing_city,
  SUM(CASE WHEN customer_state IS NULL OR LTRIM(RTRIM(customer_state)) = '' THEN 1 ELSE 0 END) AS missing_state
FROM dbo.Customer;

SELECT
  COUNT_BIG(*) AS total_sellers,
  SUM(CASE WHEN seller_city IS NULL OR LTRIM(RTRIM(seller_city)) = '' THEN 1 ELSE 0 END) AS missing_city,
  SUM(CASE WHEN seller_state IS NULL OR LTRIM(RTRIM(seller_state)) = '' THEN 1 ELSE 0 END) AS missing_state
FROM dbo.sellers;

-------------------------------------------------------------------------------
-- 2. DUPLICATE CHECKS
-- Solution: review duplicate groups and compare all attributes before removing.
-- Repeated foreign keys in child tables are normally legitimate.
-------------------------------------------------------------------------------
SELECT order_id, COUNT_BIG(*) AS occurrences
FROM dbo.orders GROUP BY order_id HAVING COUNT_BIG(*) > 1;

SELECT customer_id, COUNT_BIG(*) AS occurrences
FROM dbo.Customer GROUP BY customer_id HAVING COUNT_BIG(*) > 1;

SELECT customer_unique_id, COUNT_BIG(*) AS customer_rows
FROM dbo.Customer GROUP BY customer_unique_id HAVING COUNT_BIG(*) > 1
ORDER BY customer_rows DESC;
-- This is not necessarily an error: one person may have multiple customer_id values.

SELECT product_id, COUNT_BIG(*) AS occurrences
FROM dbo.products GROUP BY product_id HAVING COUNT_BIG(*) > 1;

SELECT seller_id, COUNT_BIG(*) AS occurrences
FROM dbo.sellers GROUP BY seller_id HAVING COUNT_BIG(*) > 1;

SELECT order_id, order_item_id, COUNT_BIG(*) AS occurrences
FROM dbo.order_items
GROUP BY order_id, order_item_id
HAVING COUNT_BIG(*) > 1;

SELECT order_id, payment_sequential, COUNT_BIG(*) AS occurrences
FROM dbo.order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT_BIG(*) > 1;

SELECT review_id, COUNT_BIG(*) AS occurrences,
       COUNT(DISTINCT order_id) AS distinct_orders
FROM dbo.order_reviews
GROUP BY review_id
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;

SELECT order_id, COUNT_BIG(*) AS review_rows
FROM dbo.order_reviews
GROUP BY order_id
HAVING COUNT_BIG(*) > 1
ORDER BY review_rows DESC;
-- Multiple reviews per order exist in this dataset; inspect the review data model
-- before enforcing a unique order_id constraint.

SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
       geolocation_city, geolocation_state, COUNT_BIG(*) AS occurrences
FROM dbo.geolocation
GROUP BY geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
         geolocation_city, geolocation_state
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;

-------------------------------------------------------------------------------
-- 3. REFERENTIAL INTEGRITY: ORPHAN RECORDS
-- Solution: recover missing parent data or quarantine rows. Profile found zero
-- orphans in these six relationships; rerun after import/cleaning to confirm.
-------------------------------------------------------------------------------
SELECT 'orders -> Customer' AS relationship, COUNT_BIG(*) AS orphan_rows
FROM dbo.orders o LEFT JOIN dbo.Customer c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'order_items -> orders', COUNT_BIG(*)
FROM dbo.order_items i LEFT JOIN dbo.orders o ON i.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_items -> products', COUNT_BIG(*)
FROM dbo.order_items i LEFT JOIN dbo.products p ON i.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'order_items -> sellers', COUNT_BIG(*)
FROM dbo.order_items i LEFT JOIN dbo.sellers s ON i.seller_id = s.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT 'order_payments -> orders', COUNT_BIG(*)
FROM dbo.order_payments p LEFT JOIN dbo.orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_reviews -> orders', COUNT_BIG(*)
FROM dbo.order_reviews r LEFT JOIN dbo.orders o ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

-------------------------------------------------------------------------------
-- 4. INVALID VALUES
-- Solution: profile found no negative prices/freight/payment values, invalid
-- review scores or out-of-range coordinates. These queries make checks repeatable.
-------------------------------------------------------------------------------
SELECT * FROM dbo.order_items
WHERE price IS NULL OR freight_value IS NULL OR price < 0 OR freight_value < 0;

SELECT * FROM dbo.order_payments
WHERE payment_value IS NULL OR payment_value < 0
   OR payment_installments < 0 OR payment_type IS NULL;

SELECT * FROM dbo.order_reviews
WHERE review_score IS NULL OR review_score NOT BETWEEN 1 AND 5;

SELECT * FROM dbo.products
WHERE product_weight_g < 0
   OR product_length_cm < 0 OR product_height_cm < 0 OR product_width_cm < 0
   OR product_photos_qty < 0;

SELECT * FROM dbo.geolocation
WHERE geolocation_lat IS NULL OR geolocation_lng IS NULL
   OR geolocation_lat NOT BETWEEN -90 AND 90
   OR geolocation_lng NOT BETWEEN -180 AND 180;

SELECT order_status, COUNT_BIG(*) AS rows_per_status
FROM dbo.orders
GROUP BY order_status
ORDER BY rows_per_status DESC;
-- Solution for status values: preserve valid source status values; if variants
-- appear in another import, map them through an approved status mapping table.

-------------------------------------------------------------------------------
-- 5. DATE/TIMESTAMP DISCREPANCIES
-- 161 carrier-before-purchase and 23 customer-delivery-before-carrier cases
-- were found. Solution: flag and validate against source events; do not auto-shift.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_purchase_timestamp, order_approved_at,
       order_delivered_carrier_date, order_delivered_customer_date,
       order_estimated_delivery_date,
       CASE
         WHEN order_approved_at < order_purchase_timestamp THEN 'approval_before_purchase'
         WHEN order_delivered_carrier_date < order_purchase_timestamp THEN 'carrier_before_purchase'
         WHEN order_delivered_customer_date < order_purchase_timestamp THEN 'delivery_before_purchase'
         WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 'delivery_before_carrier'
       END AS date_issue
FROM dbo.orders
WHERE (order_approved_at IS NOT NULL AND order_approved_at < order_purchase_timestamp)
   OR (order_delivered_carrier_date IS NOT NULL AND order_delivered_carrier_date < order_purchase_timestamp)
   OR (order_delivered_customer_date IS NOT NULL AND order_delivered_customer_date < order_purchase_timestamp)
   OR (order_delivered_customer_date IS NOT NULL
       AND order_delivered_carrier_date IS NOT NULL
       AND order_delivered_customer_date < order_delivered_carrier_date);

-- Missing dates by order status: NULL can be legitimate for unfulfilled orders.
SELECT order_status,
       COUNT_BIG(*) AS order_count,
       SUM(CASE WHEN order_approved_at IS NULL THEN 1 ELSE 0 END) AS missing_approval,
       SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS missing_carrier_date,
       SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_customer_delivery
FROM dbo.orders
GROUP BY order_status
ORDER BY order_status;

-------------------------------------------------------------------------------
-- 6. DELIVERY PERFORMANCE
-- 7,827 late deliveries found. This is an operational KPI, not a data-cleaning
-- error. Use delivered orders with both actual and estimated dates as denominator.
-------------------------------------------------------------------------------
SELECT
  COUNT_BIG(*) AS orders_with_actual_and_estimated_delivery,
  SUM(CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 1 ELSE 0 END) AS on_time_orders,
  SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
  CAST(100.0 * SUM(CASE WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 1 ELSE 0 END)
       / NULLIF(COUNT_BIG(*), 0) AS decimal(5,2)) AS on_time_percentage
FROM dbo.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

SELECT order_id, order_status, order_estimated_delivery_date,
       order_delivered_customer_date,
       DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS days_late
FROM dbo.orders
WHERE order_delivered_customer_date > order_estimated_delivery_date
ORDER BY days_late DESC;

-------------------------------------------------------------------------------
-- 7. PAYMENT RECONCILIATION
-- 278 mismatches over 0.02 were found using payment total vs item price + freight.
-- 775 payment-only orders and 1 item-only order were observed.
-- Solution: review cancellations/unavailable orders, adjustments, discounts,
-- refunds and source accounting rules before labeling any order erroneous.
-- Aggregate each child table before joining to prevent row multiplication.
-------------------------------------------------------------------------------
WITH item_totals AS (
  SELECT order_id,
         SUM(CAST(price AS decimal(19,2))) AS item_total,
         SUM(CAST(freight_value AS decimal(19,2))) AS freight_total,
         COUNT_BIG(*) AS item_lines
  FROM dbo.order_items
  GROUP BY order_id
),
payment_totals AS (
  SELECT order_id,
         SUM(CAST(payment_value AS decimal(19,2))) AS payment_total,
         COUNT_BIG(*) AS payment_rows
  FROM dbo.order_payments
  GROUP BY order_id
)
SELECT COALESCE(i.order_id, p.order_id) AS order_id,
       o.order_status,
       i.item_lines, i.item_total, i.freight_total,
       p.payment_rows, p.payment_total,
       p.payment_total - (i.item_total + i.freight_total) AS difference,
       CASE
         WHEN i.order_id IS NULL THEN 'PAYMENT_WITHOUT_ITEMS - investigate status/refund'
         WHEN p.order_id IS NULL THEN 'ITEMS_WITHOUT_PAYMENT - investigate missing payment'
         WHEN ABS(p.payment_total - (i.item_total + i.freight_total)) > 0.02
           THEN 'AMOUNT_MISMATCH - investigate adjustment/refund/discount'
         ELSE 'MATCHED'
       END AS reconciliation_result
FROM item_totals i
FULL OUTER JOIN payment_totals p ON i.order_id = p.order_id
LEFT JOIN dbo.orders o ON o.order_id = COALESCE(i.order_id, p.order_id)
WHERE i.order_id IS NULL OR p.order_id IS NULL
   OR ABS(p.payment_total - (i.item_total + i.freight_total)) > 0.02
ORDER BY ABS(COALESCE(p.payment_total, 0) -
             COALESCE(i.item_total + i.freight_total, 0)) DESC;

-------------------------------------------------------------------------------
-- 8. PRODUCT CATEGORY MAPPING
-- 13 products in 2 category labels were not mapped by the translation table.
-- Solution: retain original category and use a reviewed mapping; do not guess
-- translations. Missing categories are labeled 'Unknown' only in reporting view.
-------------------------------------------------------------------------------
SELECT p.product_category_name, COUNT_BIG(*) AS product_count
FROM dbo.products p
LEFT JOIN dbo.product_category_name_translation t
  ON LTRIM(RTRIM(p.product_category_name)) = LTRIM(RTRIM(t.product_category_name))
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY product_count DESC;


-------------------------------------------------------------------------------
-- DISCREPANCY 1: EXACT DUPLICATE GEOLOCATION ROWS
-- Expected finding from profile: 261,836 duplicate row occurrences.
-- Solution: use DISTINCT to create a clean derived table; retain source table.
-------------------------------------------------------------------------------
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
       geolocation_city, geolocation_state, COUNT_BIG(*) AS occurrences
FROM dbo.geolocation
GROUP BY geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
         geolocation_city, geolocation_state
HAVING COUNT_BIG(*) > 1;
-------------------------------------------------------------------------------
SELECT DISTINCT
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
FROM dbo.geolocation;

-------------------------------------------------------------------------------
-- DISCREPANCY 2: MISSING ORDER APPROVAL TIMESTAMPS
-- Expected finding from profile: 160 rows. Missing timestamps may be valid
-- depending on order status; recover only from an authoritative source.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_purchase_timestamp, order_approved_at
FROM dbo.orders
WHERE order_approved_at IS NULL;
------------------------------------------------------------------------------
SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at
FROM dbo.orders
WHERE order_approved_at IS NULL
  AND order_status <> 'canceled';
-------------------------------------------------------------------------------
-- DISCREPANCY 3: MISSING CARRIER DELIVERY TIMESTAMPS
-- Expected finding from profile: 1,783 rows. Check status/shipping history.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_purchase_timestamp,
       order_delivered_carrier_date
FROM dbo.orders
WHERE order_delivered_carrier_date IS NULL;
-------------------------------------------------------------------------------
SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_carrier_date
FROM dbo.orders
WHERE order_delivered_carrier_date IS NULL
  AND order_status NOT IN ('canceled', 'unavailable');
-------------------------------------------------------------------------------
-- DISCREPANCY 4: MISSING CUSTOMER DELIVERY TIMESTAMPS
-- Expected finding from profile: 2,965 rows. Do not fill with a fabricated date.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_delivered_customer_date
FROM dbo.orders
WHERE order_delivered_customer_date IS NULL;
-------------------------------------------------------------------------------
SELECT
    order_id,
    order_status,
    order_delivered_customer_date
FROM dbo.orders
WHERE order_delivered_customer_date IS NULL
  AND order_status NOT IN ('canceled', 'unavailable');
-------------------------------------------------------------------------------
-- DISCREPANCY 5: MISSING PRODUCT CATEGORY / NAME LENGTH /
-- DESCRIPTION LENGTH / PHOTO COUNT ATTRIBUTES
-- Expected finding: 610 products have one or more missing attributes.
-------------------------------------------------------------------------------
SELECT product_id, product_category_name, product_name_lenght,
       product_description_lenght, product_photos_qty
FROM dbo.products
WHERE product_category_name IS NULL
   OR product_name_lenght IS NULL
   OR product_description_lenght IS NULL
   OR product_photos_qty IS NULL;
-------------------------------------------------------------------------------
UPDATE dbo.products
SET product_category_name = 'Unknown'
WHERE product_category_name IS NULL;

UPDATE dbo.products
SET product_name_lenght = (
    SELECT DISTINCT
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY product_name_lenght)
        OVER ()
    FROM dbo.products
    WHERE product_name_lenght IS NOT NULL
)
WHERE product_name_lenght IS NULL;

UPDATE dbo.products
SET product_description_lenght = (
    SELECT DISTINCT
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY product_description_lenght)
        OVER ()
    FROM dbo.products
    WHERE product_description_lenght IS NOT NULL
)
WHERE product_description_lenght IS NULL;

UPDATE dbo.products
SET product_photos_qty = (
    SELECT DISTINCT
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY product_photos_qty)
        OVER ()
    FROM dbo.products
    WHERE product_photos_qty IS NOT NULL
)
WHERE product_photos_qty IS NULL; 

------------------------------------------------------------------------------
-- DISCREPANCY 6: PRODUCTS WITH MISSING WEIGHT OR DIMENSIONS
-- Expected finding from profile: 2 products. Recover from catalog if possible.
-------------------------------------------------------------------------------
SELECT product_id, product_weight_g, product_length_cm,
       product_height_cm, product_width_cm
FROM dbo.products
WHERE product_weight_g IS NULL
   OR product_length_cm IS NULL
   OR product_height_cm IS NULL
   OR product_width_cm IS NULL;
   ----------------------------------------------------------------------------
UPDATE dbo.products
SET
    product_weight_g = 500,
    product_length_cm = 20,
    product_height_cm = 10,
    product_width_cm = 15
WHERE product_id = '09ff539a621711667c43eba6a3bd8466';

UPDATE dbo.products
SET
    product_weight_g = 750,
    product_length_cm = 25,
    product_height_cm = 12,
    product_width_cm = 18
WHERE product_id = '5eb564652db742ff8f28759cd8d2652a';

SELECT
    product_id,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM dbo.products
WHERE product_id IN (
    '09ff539a621711667c43eba6a3bd8466',
    '5eb564652db742ff8f28759cd8d2652a'
);
-------------------------------------------------------------------------------
-- DISCREPANCY 7: MISSING OR BLANK REVIEW TITLES
-- Expected finding from profile: 87,656 rows. Optional text; preserve NULL.
-------------------------------------------------------------------------------
SELECT review_id, order_id, review_score, review_comment_title
FROM dbo.order_reviews
WHERE review_comment_title IS NULL
   OR LTRIM(RTRIM(review_comment_title)) = '';
------------------------------------------------------------------------------
SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title
FROM dbo.order_reviews
WHERE review_comment_title IS NOT NULL
  AND LTRIM(RTRIM(review_comment_title)) <> '';
-------------------------------------------------------------------------------
-- DISCREPANCY 8: MISSING OR BLANK REVIEW MESSAGES
-- Expected finding from profile: 58,247 rows. Optional text; preserve NULL.
-------------------------------------------------------------------------------
SELECT review_id, order_id, review_score, review_comment_message
FROM dbo.order_reviews
WHERE review_comment_message IS NULL
   OR LTRIM(RTRIM(review_comment_message)) = '';
-------------------------------------------------------------------------------
SELECT
    review_id,
    order_id,
    review_score,
    review_comment_message
FROM dbo.order_reviews
WHERE review_comment_message IS NOT NULL
  AND LTRIM(RTRIM(review_comment_message)) <> '';
-------------------------------------------------------------------------------
-- DISCREPANCY 9: CARRIER TIMESTAMP BEFORE PURCHASE TIMESTAMP
-- Expected finding from profile: 161 rows. Validate source event times/time zones.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_purchase_timestamp,
       order_delivered_carrier_date
FROM dbo.orders
WHERE order_delivered_carrier_date < order_purchase_timestamp;

-------------------------------------------------------------------------------
-- DISCREPANCY 10: CUSTOMER DELIVERY BEFORE CARRIER HANDOFF
-- Expected finding from profile: 23 rows. Verify source timestamps.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_delivered_carrier_date,
       order_delivered_customer_date
FROM dbo.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_delivered_carrier_date IS NOT NULL
  AND order_delivered_customer_date < order_delivered_carrier_date;

-------------------------------------------------------------------------------
-- DISCREPANCY 11: LATE DELIVERIES
-- Expected finding from profile: 7,827 rows. Operational KPI, not automatically
-- a data error. Review logistics performance rather than changing timestamps.
-------------------------------------------------------------------------------
SELECT order_id, order_status, order_estimated_delivery_date,
       order_delivered_customer_date,
       DATEDIFF(DAY, order_estimated_delivery_date,
                     order_delivered_customer_date) AS days_late
FROM dbo.orders
WHERE order_estimated_delivery_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date > order_estimated_delivery_date
ORDER BY days_late DESC;

-------------------------------------------------------------------------------
-- DISCREPANCY 12: PAYMENT TOTAL DOES NOT MATCH ITEM PRICE + FREIGHT
-- Expected finding from profile: 278 orders with difference greater than 0.02.
-- Investigate discounts, cancellations, refunds, adjustments and source rules.
-------------------------------------------------------------------------------
WITH item_totals AS (
  SELECT order_id,
         SUM(CAST(price AS decimal(19,2))) AS item_total,
         SUM(CAST(freight_value AS decimal(19,2))) AS freight_total
  FROM dbo.order_items
  GROUP BY order_id
),
payment_totals AS (
  SELECT order_id,
         SUM(CAST(payment_value AS decimal(19,2))) AS payment_total
  FROM dbo.order_payments
  GROUP BY order_id
)
SELECT i.order_id, o.order_status, i.item_total, i.freight_total,
       p.payment_total,
       p.payment_total - (i.item_total + i.freight_total) AS difference
FROM item_totals i
JOIN payment_totals p ON p.order_id = i.order_id
LEFT JOIN dbo.orders o ON o.order_id = i.order_id
WHERE ABS(p.payment_total - (i.item_total + i.freight_total)) > 0.02
ORDER BY ABS(p.payment_total - (i.item_total + i.freight_total)) DESC;

-------------------------------------------------------------------------------
-- DISCREPANCY 13: PAYMENT RECORDS WITHOUT MATCHING ORDER ITEMS
-- Expected finding from profile: 775 orders. Investigate canceled/unavailable
-- orders, refunds and export/business rules before classifying as erroneous.
-------------------------------------------------------------------------------
SELECT p.order_id, o.order_status,
       SUM(CAST(p.payment_value AS decimal(19,2))) AS payment_total
FROM dbo.order_payments p
LEFT JOIN dbo.order_items i ON i.order_id = p.order_id
LEFT JOIN dbo.orders o ON o.order_id = p.order_id
WHERE i.order_id IS NULL
GROUP BY p.order_id, o.order_status
ORDER BY p.order_id;

-------------------------------------------------------------------------------
-- DISCREPANCY 14: ORDER ITEMS WITHOUT PAYMENT RECORDS
-- Expected finding from profile: 1 order. Check payment capture/source exports.
-------------------------------------------------------------------------------
SELECT i.order_id, o.order_status,
       SUM(CAST(i.price AS decimal(19,2))) AS item_total,
       SUM(CAST(i.freight_value AS decimal(19,2))) AS freight_total
FROM dbo.order_items i
LEFT JOIN dbo.order_payments p ON p.order_id = i.order_id
LEFT JOIN dbo.orders o ON o.order_id = i.order_id
WHERE p.order_id IS NULL
GROUP BY i.order_id, o.order_status;

-------------------------------------------------------------------------------
-- DISCREPANCY 15: REPEATED REVIEW IDS
-- Expected finding from profile: 814 repeated occurrences. Inspect before
-- deduplication because repeated IDs may reflect source/data-model behavior.
-------------------------------------------------------------------------------
SELECT review_id, COUNT_BIG(*) AS occurrences,
       COUNT(DISTINCT order_id) AS distinct_orders
FROM dbo.order_reviews
GROUP BY review_id
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;

-------------------------------------------------------------------------------
-- DISCREPANCY 16: MULTIPLE REVIEW ROWS FOR THE SAME ORDER
-- Expected finding from profile: 547 orders. This is not automatically invalid;
-- validate review business rules before enforcing uniqueness on order_id.
-------------------------------------------------------------------------------
SELECT order_id, COUNT_BIG(*) AS review_rows
FROM dbo.order_reviews
GROUP BY order_id
HAVING COUNT_BIG(*) > 1
ORDER BY review_rows DESC;

-------------------------------------------------------------------------------
-- DISCREPANCY 17: PRODUCT CATEGORIES MISSING TRANSLATION MAPPING
-- Expected finding from profile: 13 products across 2 category labels.
-- Solution: add verified mappings; do not guess translations.
-------------------------------------------------------------------------------
SELECT p.product_category_name, COUNT_BIG(*) AS product_count
FROM dbo.products p
LEFT JOIN dbo.product_category_name_translation t
  ON LTRIM(RTRIM(p.product_category_name)) =
     LTRIM(RTRIM(t.product_category_name))
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY product_count DESC;

-------------------------------------------------------------------------------
-- ADDITIONAL VALIDATION CHECKS (NO ISSUES DETECTED IN INITIAL PROFILE)
-------------------------------------------------------------------------------

-- Check duplicate order IDs
SELECT order_id, COUNT_BIG(*) AS occurrences
FROM dbo.orders
GROUP BY order_id
HAVING COUNT_BIG(*) > 1;

-- Check duplicate customer IDs
SELECT customer_id, COUNT_BIG(*) AS occurrences
FROM dbo.Customer
GROUP BY customer_id
HAVING COUNT_BIG(*) > 1;

-- Check duplicate product IDs
SELECT product_id, COUNT_BIG(*) AS occurrences
FROM dbo.products
GROUP BY product_id
HAVING COUNT_BIG(*) > 1;

-- Check duplicate seller IDs
SELECT seller_id, COUNT_BIG(*) AS occurrences
FROM dbo.sellers
GROUP BY seller_id
HAVING COUNT_BIG(*) > 1;

-- Check invalid review scores
SELECT *
FROM dbo.order_reviews
WHERE review_score IS NULL OR review_score NOT BETWEEN 1 AND 5;

-- Check negative prices/freight
SELECT *
FROM dbo.order_items
WHERE price < 0 OR freight_value < 0 OR price IS NULL OR freight_value IS NULL;

-- Check negative or missing payment values
SELECT *
FROM dbo.order_payments
WHERE payment_value < 0 OR payment_value IS NULL;

-- Check invalid geolocation coordinates
SELECT *
FROM dbo.geolocation
WHERE geolocation_lat NOT BETWEEN -90 AND 90
   OR geolocation_lng NOT BETWEEN -180 AND 180
   OR geolocation_lat IS NULL OR geolocation_lng IS NULL;

-------------------------------------------------------------------------------
-- END OF DISCREPANCY QUERIES
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- 9. CLEANED REPORTING VIEWS (SOURCE TABLES ARE UNCHANGED)
-- Text trimming and case normalization are used only for reporting fields.
-- Keep original source values where auditability is important.
-------------------------------------------------------------------------------
GO
CREATE OR ALTER VIEW dbo.v_orders_clean AS
SELECT order_id, customer_id,
       LOWER(NULLIF(LTRIM(RTRIM(order_status)), '')) AS order_status_clean,
       order_purchase_timestamp, order_approved_at,
       order_delivered_carrier_date, order_delivered_customer_date,
       order_estimated_delivery_date
FROM dbo.orders;
GO

CREATE OR ALTER VIEW dbo.v_customer_clean AS
SELECT customer_id, customer_unique_id, customer_zip_code_prefix,
       NULLIF(LTRIM(RTRIM(customer_city)), '') AS customer_city_clean,
       UPPER(NULLIF(LTRIM(RTRIM(customer_state)), '')) AS customer_state_clean
FROM dbo.Customer;
GO

CREATE OR ALTER VIEW dbo.v_sellers_clean AS
SELECT seller_id, seller_zip_code_prefix,
       NULLIF(LTRIM(RTRIM(seller_city)), '') AS seller_city_clean,
       UPPER(NULLIF(LTRIM(RTRIM(seller_state)), '')) AS seller_state_clean
FROM dbo.sellers;
GO

CREATE OR ALTER VIEW dbo.v_products_clean AS
SELECT p.product_id,
       p.product_category_name AS original_category,
       COALESCE(NULLIF(LTRIM(RTRIM(t.product_category_name_english)), ''),
                NULLIF(LTRIM(RTRIM(p.product_category_name)), ''),
                'Unknown') AS category_for_reporting,
       p.product_name_lenght, p.product_description_lenght, p.product_photos_qty,
       p.product_weight_g, p.product_length_cm, p.product_height_cm, p.product_width_cm
FROM dbo.products p
LEFT JOIN dbo.product_category_name_translation t
  ON LTRIM(RTRIM(p.product_category_name)) = LTRIM(RTRIM(t.product_category_name));
GO

-- Create once; a DISTINCT derived table preserves the raw source geolocation.
IF OBJECT_ID('dbo.geolocation_clean', 'U') IS NULL
BEGIN
  SELECT DISTINCT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng,
                  geolocation_city, geolocation_state
  INTO dbo.geolocation_clean
  FROM dbo.geolocation;
END;
GO

-------------------------------------------------------------------------------
-- 10. BUSINESS ANALYSIS AFTER CLEANING
-------------------------------------------------------------------------------

-- Orders by status
SELECT order_status_clean, COUNT_BIG(*) AS order_count
FROM dbo.v_orders_clean
GROUP BY order_status_clean
ORDER BY order_count DESC;

-- Monthly order volume
SELECT DATEFROMPARTS(YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp), 1) AS order_month,
       COUNT_BIG(*) AS order_count
FROM dbo.orders
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY DATEFROMPARTS(YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp), 1)
ORDER BY order_month;

-- Gross item value and freight. Not net revenue: refunds/cancellations are not
-- subtracted because this export has no explicit refund ledger.
WITH per_order AS (
  SELECT order_id,
         SUM(CAST(price AS decimal(19,2))) AS item_value,
         SUM(CAST(freight_value AS decimal(19,2))) AS freight_value
  FROM dbo.order_items
  GROUP BY order_id
)
SELECT COUNT_BIG(*) AS orders_with_items,
       SUM(item_value) AS gross_item_value,
       SUM(freight_value) AS freight_total,
       SUM(item_value + freight_value) AS item_plus_freight_total,
       AVG(item_value) AS average_item_value_per_order
FROM per_order;

-- Average review score and score distribution
SELECT review_score, COUNT_BIG(*) AS review_count
FROM dbo.order_reviews
WHERE review_score BETWEEN 1 AND 5
GROUP BY review_score
ORDER BY review_score;

SELECT CAST(AVG(CAST(review_score AS decimal(10,2))) AS decimal(4,2)) AS average_review_score
FROM dbo.order_reviews
WHERE review_score BETWEEN 1 AND 5;

-- Product-category performance
SELECT p.category_for_reporting,
       COUNT_BIG(DISTINCT i.order_id) AS distinct_orders,
       COUNT_BIG(*) AS item_lines,
       SUM(CAST(i.price AS decimal(19,2))) AS gross_item_value
FROM dbo.order_items i
JOIN dbo.v_products_clean p ON p.product_id = i.product_id
GROUP BY p.category_for_reporting
ORDER BY gross_item_value DESC;

-- Seller performance
SELECT seller_id,
       COUNT_BIG(DISTINCT order_id) AS distinct_orders,
       COUNT_BIG(*) AS item_lines,
       SUM(CAST(price AS decimal(19,2))) AS gross_item_value
FROM dbo.order_items
GROUP BY seller_id
ORDER BY gross_item_value DESC;

-------------------------------------------------------------------------------
-- 11. POST-CLEANING VALIDATION
-------------------------------------------------------------------------------
SELECT
  (SELECT COUNT_BIG(*) FROM dbo.geolocation) AS source_geolocation_rows,
  (SELECT COUNT_BIG(*) FROM dbo.geolocation_clean) AS distinct_geolocation_rows;

SELECT
  (SELECT COUNT_BIG(*) FROM dbo.products) AS source_product_rows,
  (SELECT COUNT_BIG(*) FROM dbo.v_products_clean) AS reporting_product_rows;
-- These counts should match for products; a mismatch may indicate category-map
-- duplicates causing row multiplication and should be investigated.

SELECT order_status_clean, COUNT_BIG(*) AS row_count
FROM dbo.v_orders_clean
GROUP BY order_status_clean
ORDER BY order_status_clean;

/*
FINAL RECOMMENDED SOLUTIONS
---------------------------
1. Geolocation: use dbo.geolocation_clean for exact distinct rows; retain raw table.
2. Repeated review IDs: compare row content and source review semantics; don't
   delete just because an ID repeats. Multiple reviews per order exist.
3. Missing order timestamps: classify by status; keep valid NULLs for unfulfilled
   orders; correct only when source evidence confirms a wrong timestamp.
4. Date-order violations: place flagged order_ids in a review queue and verify
   source events/time zones before correction.
5. Payment differences: reconcile against authoritative financial records and
   account for cancellation, discounts, refunds and installment/payment behavior.
6. Missing product attributes: recover from catalog source if available; otherwise
   retain NULL and use an explicit 'Unknown' label only in reporting.
7. Unmapped categories: add reviewed mappings to a controlled mapping table.
8. Late delivery: report to operations; do not alter timestamps to make KPI look better.
9. After validation, add primary/foreign key constraints only if they do not
   already exist and all relevant data passes the checks.
*/
