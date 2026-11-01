USE BrazilianEcommerce;
GO

-- Analysis 1: Monthly orders and revenue

WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price) AS item_revenue,
        SUM(freight_value) AS freight_revenue
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    YEAR(o.order_purchase_timestamp) AS order_year,
    MONTH(o.order_purchase_timestamp) AS order_month,
    COUNT(*) AS total_orders,
    COUNT(ot.order_id) AS orders_with_items,
    SUM(COALESCE(ot.item_revenue, 0)) AS item_revenue,
    SUM(COALESCE(ot.freight_revenue, 0)) AS freight_revenue,
    SUM(
        COALESCE(ot.item_revenue, 0)
        + COALESCE(ot.freight_revenue, 0)
    ) AS total_order_value,
    CAST(
        AVG(
            CASE WHEN ot.order_id IS NOT NULL
                 THEN ot.item_revenue + ot.freight_revenue
            END
        ) AS DECIMAL(18,2)
    ) AS average_order_value
FROM dbo.orders AS o
LEFT JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY
    YEAR(o.order_purchase_timestamp),
    MONTH(o.order_purchase_timestamp)
ORDER BY
    order_year,
    order_month;
---------------------------------------------------------

-- Analysis 2: Month-over-month performance

WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_value
    FROM dbo.order_items
    GROUP BY order_id
),
MonthlySales AS (
    SELECT
        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        ) AS sales_month,
        COUNT(*) AS total_orders,
        SUM(COALESCE(ot.order_value, 0)) AS total_revenue
    FROM dbo.orders AS o
    LEFT JOIN OrderTotals AS ot
        ON o.order_id = ot.order_id
    WHERE o.order_purchase_timestamp IS NOT NULL
    GROUP BY
        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        )
),
MonthlyComparison AS (
    SELECT
        sales_month,
        total_orders,
        total_revenue,
        LAG(total_orders) OVER (
            ORDER BY sales_month
        ) AS previous_month_orders,
        LAG(total_revenue) OVER (
            ORDER BY sales_month
        ) AS previous_month_revenue
    FROM MonthlySales
)
SELECT
    sales_month,
    total_orders,
    total_revenue,
    previous_month_orders,
    previous_month_revenue,
    CAST(
        100.0 * (total_orders - previous_month_orders)
        / NULLIF(previous_month_orders, 0)
        AS DECIMAL(10,2)
    ) AS order_growth_pct,
    CAST(
        100.0 * (total_revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0)
        AS DECIMAL(10,2)
    ) AS revenue_growth_pct
FROM MonthlyComparison
ORDER BY sales_month;
------------------------------------------------------

-- Analysis 3: Annual sales summary

WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_value
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    YEAR(o.order_purchase_timestamp) AS order_year,
    COUNT(*) AS total_orders,
    SUM(COALESCE(ot.order_value, 0)) AS total_revenue,
    CAST(
        AVG(
            CASE WHEN ot.order_id IS NOT NULL
                 THEN ot.order_value
            END
        ) AS DECIMAL(18,2)
    ) AS average_order_value
FROM dbo.orders AS o
LEFT JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY YEAR(o.order_purchase_timestamp)
ORDER BY order_year;
------------------------------------------------------

-- Analysis 4: Orders and revenue by weekday

SET DATEFIRST 1;

WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_value
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    DATENAME(
        WEEKDAY,
        o.order_purchase_timestamp
    ) AS weekday_name,
    DATEPART(
        WEEKDAY,
        o.order_purchase_timestamp
    ) AS weekday_number,
    COUNT(*) AS total_orders,
    SUM(COALESCE(ot.order_value, 0)) AS total_revenue
FROM dbo.orders AS o
LEFT JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY
    DATENAME(WEEKDAY, o.order_purchase_timestamp),
    DATEPART(WEEKDAY, o.order_purchase_timestamp)
ORDER BY weekday_number;
------------------------------------------------------------

-- Analysis 5: Orders by purchase hour

SELECT
    DATEPART(
        HOUR,
        order_purchase_timestamp
    ) AS purchase_hour,
    COUNT(*) AS total_orders
FROM dbo.orders
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY
    DATEPART(HOUR, order_purchase_timestamp)
ORDER BY purchase_hour;
---------------------------------------------------------------

-- Analysis 6: Revenue and order status

WITH OrderTotals AS (
    SELECT
        order_id,
        SUM(price) AS item_revenue,
        SUM(freight_value) AS freight_revenue
    FROM dbo.order_items
    GROUP BY order_id
)
SELECT
    o.order_status,
    COUNT(*) AS total_orders,
    SUM(COALESCE(ot.item_revenue, 0)) AS item_revenue,
    SUM(COALESCE(ot.freight_revenue, 0)) AS freight_revenue,
    SUM(
        COALESCE(ot.item_revenue, 0)
        + COALESCE(ot.freight_revenue, 0)
    ) AS total_order_value
FROM dbo.orders AS o
LEFT JOIN OrderTotals AS ot
    ON o.order_id = ot.order_id
GROUP BY o.order_status
ORDER BY total_order_value DESC;
----------------------------------------------------------------

