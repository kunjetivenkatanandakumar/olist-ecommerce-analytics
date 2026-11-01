USE BrazilianEcommerce;
GO

-- A1: Sales performance by customer state
WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price) AS item_revenue,
        SUM(freight_value) AS freight_revenue
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    SUM(COALESCE(ot.item_revenue, 0)) AS item_revenue,
    SUM(COALESCE(ot.freight_revenue, 0)) AS freight_revenue,
    SUM(
        COALESCE(ot.item_revenue, 0)
        + COALESCE(ot.freight_revenue, 0)
    ) AS total_order_value,
    CAST(
        SUM(COALESCE(ot.item_revenue, 0))
        / NULLIF(COUNT(DISTINCT o.order_id) * 1.0, 0)
        AS DECIMAL(18,2)
    ) AS item_revenue_per_order
FROM dbo.Customer AS c
JOIN dbo.orders AS o
    ON c.customer_id = o.customer_id
LEFT JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
GROUP BY c.customer_state
ORDER BY total_order_value DESC;

-- B1: Top 10 cities by order-item value
WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price) AS item_revenue,
        SUM(freight_value) AS freight_revenue
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT TOP 10
    c.customer_city,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    SUM(COALESCE(ot.item_revenue, 0)) AS item_revenue,
    SUM(COALESCE(ot.freight_revenue, 0)) AS freight_revenue,
    SUM(
        COALESCE(ot.item_revenue, 0)
        + COALESCE(ot.freight_revenue, 0)
    ) AS total_order_value
FROM dbo.Customer AS c
JOIN dbo.orders AS o
    ON c.customer_id = o.customer_id
LEFT JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
GROUP BY
    c.customer_city,
    c.customer_state
ORDER BY total_order_value DESC;

-- C1: Freight analysis by customer state
WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price) AS item_revenue,
        SUM(freight_value) AS freight_revenue
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_orders,
    CAST(
        AVG(CAST(ot.freight_revenue AS DECIMAL(18,2)))
        AS DECIMAL(18,2)
    ) AS average_freight_per_order,
    CAST(
        SUM(ot.freight_revenue)
        AS DECIMAL(18,2)
    ) AS total_freight,
    CAST(
        100.0 * SUM(ot.freight_revenue)
        / NULLIF(SUM(ot.item_revenue), 0)
        AS DECIMAL(10,2)
    ) AS freight_as_percentage_of_item_revenue
FROM dbo.Customer AS c
JOIN dbo.orders AS o
    ON c.customer_id = o.customer_id
JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
GROUP BY c.customer_state
ORDER BY freight_as_percentage_of_item_revenue DESC;

-- D1: Delivery performance by customer state
WITH DeliveryData AS (
    SELECT
        c.customer_state,
        o.order_id,
        DATEDIFF(
            DAY,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) AS delivery_days,
        CASE
            WHEN o.order_delivered_customer_date
                 <= o.order_estimated_delivery_date
                THEN 0
            ELSE 1
        END AS is_late
    FROM dbo.Customer AS c
    JOIN dbo.orders AS o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
      AND o.order_delivered_customer_date
          >= o.order_purchase_timestamp
)
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    SUM(is_late) AS late_orders,
    CAST(
        100.0 * SUM(is_late) / NULLIF(COUNT(*), 0)
        AS DECIMAL(6,2)
    ) AS late_delivery_percentage,
    CAST(
        AVG(CAST(delivery_days AS DECIMAL(10,2)))
        AS DECIMAL(10,2)
    ) AS average_delivery_days
FROM DeliveryData
GROUP BY customer_state
ORDER BY late_delivery_percentage DESC;

-- E1: Review scores by customer state
WITH OrderReviews AS (
    SELECT
        order_id,
        AVG(CAST(review_score AS DECIMAL(5,2)))
            AS average_review_score
    FROM dbo.order_reviews
    WHERE review_score BETWEEN 1 AND 5
    GROUP BY order_id
)
SELECT
    c.customer_state,
    COUNT(*) AS reviewed_orders,
    CAST(
        AVG(r.average_review_score)
        AS DECIMAL(4,2)
    ) AS average_review_score,
    SUM(
        CASE WHEN r.average_review_score <= 2
             THEN 1 ELSE 0 END
    ) AS orders_with_low_average_score,
    CAST(
        100.0 * SUM(
            CASE WHEN r.average_review_score <= 2
                 THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(*), 0)
        AS DECIMAL(6,2)
    ) AS low_score_percentage
FROM dbo.Customer AS c
JOIN dbo.orders AS o
    ON c.customer_id = o.customer_id
JOIN OrderReviews AS r
    ON o.order_id = r.order_id
GROUP BY c.customer_state
ORDER BY average_review_score ASC;

