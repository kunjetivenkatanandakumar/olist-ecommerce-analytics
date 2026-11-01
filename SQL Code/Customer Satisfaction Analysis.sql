-- D1: Payment method summary
SELECT
    payment_type,
    COUNT(*) AS payment_records,
    COUNT(DISTINCT order_id) AS distinct_orders,
    SUM(payment_value) AS total_payment_value,
    AVG(CAST(payment_value AS DECIMAL(18,2)))
        AS average_payment_record_value
FROM dbo.order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

-- D2: Payment installments
SELECT
    payment_type,
    payment_installments,
    COUNT(*) AS payment_records,
    AVG(CAST(payment_value AS DECIMAL(18,2)))
        AS average_payment_value
FROM dbo.order_payments
GROUP BY
    payment_type,
    payment_installments
ORDER BY
    payment_type,
    payment_installments;

-- D3: Satisfaction by payment method
WITH OrderReviews AS (
    SELECT
        order_id,
        AVG(CAST(review_score AS DECIMAL(5,2)))
            AS average_review_score
    FROM dbo.order_reviews
    WHERE review_score BETWEEN 1 AND 5
    GROUP BY order_id
),
OrderPaymentMethods AS (
    SELECT DISTINCT
        order_id,
        payment_type
    FROM dbo.order_payments
    WHERE payment_type IS NOT NULL
)
SELECT
    p.payment_type,
    COUNT(*) AS reviewed_orders,
    CAST(
        AVG(r.average_review_score)
        AS DECIMAL(4,2)
    ) AS average_review_score,
    CAST(
        100.0 * SUM(
            CASE WHEN r.average_review_score <= 2
                 THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(*), 0)
        AS DECIMAL(6,2)
    ) AS low_score_order_percentage
FROM OrderPaymentMethods AS p
JOIN OrderReviews AS r
    ON p.order_id = r.order_id
GROUP BY p.payment_type
ORDER BY average_review_score DESC;

-- E1: Review response time
SELECT
    COUNT(*) AS reviews_with_response,
    CAST(
        AVG(CAST(
            DATEDIFF(
                HOUR,
                review_creation_date,
                review_answer_timestamp
            ) AS DECIMAL(10,2)
        ))
        AS DECIMAL(10,2)
    ) AS average_response_hours,
    SUM(
        CASE
            WHEN DATEDIFF(
                HOUR,
                review_creation_date,
                review_answer_timestamp
            ) <= 24 THEN 1
            ELSE 0
        END
    ) AS responses_within_24_hours
FROM dbo.order_reviews
WHERE review_creation_date IS NOT NULL
  AND review_answer_timestamp IS NOT NULL
  AND review_answer_timestamp >= review_creation_date;

-- F1: Satisfaction by delivery result and payment method
WITH OrderReviews AS (
    SELECT
        order_id,
        AVG(CAST(review_score AS DECIMAL(5,2)))
            AS average_review_score
    FROM dbo.order_reviews
    WHERE review_score BETWEEN 1 AND 5
    GROUP BY order_id
),
OrderPaymentMethods AS (
    SELECT DISTINCT
        order_id,
        payment_type
    FROM dbo.order_payments
    WHERE payment_type IS NOT NULL
),
DeliveryAnalysis AS (
    SELECT
        order_id,
        CASE
            WHEN order_delivered_customer_date
                 <= order_estimated_delivery_date
                THEN 'On time or early'
            ELSE 'Late'
        END AS delivery_result
    FROM dbo.orders
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    d.delivery_result,
    p.payment_type,
    COUNT(*) AS reviewed_orders,
    CAST(
        AVG(r.average_review_score)
        AS DECIMAL(4,2)
    ) AS average_review_score
FROM DeliveryAnalysis AS d
JOIN OrderPaymentMethods AS p
    ON d.order_id = p.order_id
JOIN OrderReviews AS r
    ON d.order_id = r.order_id
GROUP BY
    d.delivery_result,
    p.payment_type
ORDER BY
    d.delivery_result,
    average_review_score DESC;
-------------------------------------------------------------

SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,

    CASE
        WHEN c.customer_id IS NULL
          OR c.customer_unique_id IS NULL
          OR c.customer_zip_code_prefix IS NULL
          OR c.customer_city IS NULL
          OR c.customer_state IS NULL
          OR TRIM(c.customer_city) = ''
          OR TRIM(c.customer_state) = ''
        THEN 1

        WHEN COUNT(*) OVER (
            PARTITION BY c.customer_id
        ) > 1
        THEN 1

        WHEN NOT EXISTS (
            SELECT 1
            FROM geolocation g
            WHERE g.geolocation_zip_code_prefix =
                  c.customer_zip_code_prefix
              AND LOWER(TRIM(g.geolocation_city)) =
                  LOWER(TRIM(c.customer_city))
              AND UPPER(TRIM(g.geolocation_state)) =
                  UPPER(TRIM(c.customer_state))
        )
        THEN 1

        ELSE 0
    END AS flag

FROM customer c;
--------------------------------------------------------------


ALTER TABLE geolocation
ADD flag INT;


WITH LocationCheck AS
(
    SELECT
        geolocation_zip_code_prefix,
        COUNT(DISTINCT
            CONCAT(
                LOWER(LTRIM(RTRIM(geolocation_city))),
                '|',
                UPPER(LTRIM(RTRIM(geolocation_state)))
            )
        ) AS location_count
    FROM geolocation
    GROUP BY geolocation_zip_code_prefix
)

UPDATE g
SET flag =
    CASE
        WHEN g.geolocation_zip_code_prefix IS NULL
          OR g.geolocation_lat IS NULL
          OR g.geolocation_lng IS NULL
          OR g.geolocation_city IS NULL
          OR LTRIM(RTRIM(g.geolocation_city)) = ''
          OR g.geolocation_state IS NULL
          OR LTRIM(RTRIM(g.geolocation_state)) = ''
          OR g.geolocation_lat NOT BETWEEN -90 AND 90
          OR g.geolocation_lng NOT BETWEEN -180 AND 180
          OR lc.location_count > 1
        THEN 1
        ELSE 0
    END
FROM geolocation g
LEFT JOIN LocationCheck lc
    ON g.geolocation_zip_code_prefix =
       lc.geolocation_zip_code_prefix;


SELECT
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state,
    flag
FROM geolocation
WHERE flag = 1;
---------------------------------------------------

ALTER TABLE order_payments
ADD flag INT;


WITH PaymentCheck AS
(
    SELECT
        order_id,
        payment_sequential,
        COUNT(*) AS duplicate_count
    FROM order_payments
    GROUP BY
        order_id,
        payment_sequential
)

UPDATE p
SET flag =
    CASE
        WHEN p.order_id IS NULL
          OR p.payment_sequential IS NULL
          OR p.payment_sequential < 1
          OR p.payment_type IS NULL
          OR LTRIM(RTRIM(p.payment_type)) = ''
          OR LOWER(LTRIM(RTRIM(p.payment_type)))
             NOT IN (
                'credit_card',
                'boleto',
                'voucher',
                'debit_card'
             )
          OR p.payment_installments IS NULL
          OR p.payment_installments < 1
          OR p.payment_value IS NULL
          OR p.payment_value <= 0
          OR pc.duplicate_count > 1
        THEN 1
        ELSE 0
    END
FROM order_payments p
LEFT JOIN PaymentCheck pc
    ON p.order_id = pc.order_id
   AND p.payment_sequential = pc.payment_sequential;


SELECT
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value,
    flag
FROM order_payments
WHERE flag = 1;
---------------------------------------------------

IF COL_LENGTH('dbo.orders', 'flag') IS NULL
BEGIN
    ALTER TABLE dbo.orders
    ADD flag INT;
END;


;WITH OrderCheck AS
(
    SELECT
        order_id,
        COUNT(*) AS duplicate_count
    FROM dbo.orders
    GROUP BY order_id
)

UPDATE o
SET flag =
    CASE
        -- Missing mandatory information
        WHEN o.order_id IS NULL
          OR o.customer_id IS NULL
          OR o.order_status IS NULL
          OR o.order_purchase_timestamp IS NULL
        THEN 1

        -- Duplicate order ID
        WHEN oc.duplicate_count > 1
        THEN 1

        -- Invalid date sequence
        WHEN o.order_approved_at <
             o.order_purchase_timestamp
        THEN 1

        WHEN o.order_delivered_carrier_date <
             o.order_purchase_timestamp
        THEN 1

        WHEN o.order_delivered_customer_date <
             o.order_delivered_carrier_date
        THEN 1

        WHEN o.order_estimated_delivery_date <
             o.order_purchase_timestamp
        THEN 1

        -- Delivered order missing delivery dates
        WHEN o.order_status = 'delivered'
         AND (
                o.order_approved_at IS NULL
             OR o.order_delivered_carrier_date IS NULL
             OR o.order_delivered_customer_date IS NULL
         )
        THEN 1

        -- Non-delivered order has customer delivery date
        WHEN o.order_status <> 'delivered'
         AND o.order_delivered_customer_date IS NOT NULL
        THEN 1

        ELSE 0
    END
FROM dbo.orders o
LEFT JOIN OrderCheck oc
    ON o.order_id = oc.order_id;


SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    flag
FROM dbo.orders
WHERE flag = 1;
-------------------------------------------------

IF COL_LENGTH('dbo.sellers', 'flag') IS NULL
BEGIN
    ALTER TABLE dbo.sellers
    ADD flag INT;
END;


;WITH SellerCheck AS
(
    SELECT
        seller_id,
        COUNT(*) AS duplicate_count
    FROM dbo.sellers
    GROUP BY seller_id
),
LocationCheck AS
(
    SELECT
        geolocation_zip_code_prefix,
        LOWER(LTRIM(RTRIM(geolocation_city))) AS city,
        UPPER(LTRIM(RTRIM(geolocation_state))) AS state
    FROM dbo.geolocation
    GROUP BY
        geolocation_zip_code_prefix,
        LOWER(LTRIM(RTRIM(geolocation_city))),
        UPPER(LTRIM(RTRIM(geolocation_state)))
)

UPDATE s
SET flag =
    CASE
        -- Missing mandatory values
        WHEN s.seller_id IS NULL
          OR s.seller_zip_code_prefix IS NULL
          OR s.seller_city IS NULL
          OR LTRIM(RTRIM(s.seller_city)) = ''
          OR s.seller_state IS NULL
          OR LTRIM(RTRIM(s.seller_state)) = ''
        THEN 1

        -- Duplicate seller ID
        WHEN sc.duplicate_count > 1
        THEN 1

        -- Invalid state code
        WHEN LEN(LTRIM(RTRIM(s.seller_state))) <> 2
        THEN 1

        -- Location mismatch
        WHEN NOT EXISTS
        (
            SELECT 1
            FROM LocationCheck g
            WHERE g.geolocation_zip_code_prefix =
                  s.seller_zip_code_prefix
              AND g.city =
                  LOWER(LTRIM(RTRIM(s.seller_city)))
              AND g.state =
                  UPPER(LTRIM(RTRIM(s.seller_state)))
        )
        THEN 1

        ELSE 0
    END
FROM dbo.sellers s
LEFT JOIN SellerCheck sc
    ON s.seller_id = sc.seller_id;

