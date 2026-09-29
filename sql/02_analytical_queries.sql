-- 02_analytical_queries.sql
-- Nine business questions answered with SQL (CTEs, window functions, subqueries).
-- Run after 01_schema_and_sample_data.sql.

USE gentlemans_hub_db;
-- 1. Top Customer Spending Analysis
-- Business Context: Identify top spending customers within each loyalty tier to send them offers 

WITH CustomerMetrics AS (
    SELECT 
        c.CustomerID,
        CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
        la.TierLevel,
        SUM(o.TotalAmount) AS TotalSpent,
        ROUND(AVG(o.TotalAmount), 2) AS AverageOrderValue,
        COUNT(o.OrderID) AS TotalTransactions
    FROM Customer c
    JOIN `Order` o ON c.CustomerID = o.CustomerID
    JOIN LoyaltyAccount la ON c.CustomerID = la.CustomerID
    WHERE o.OrderStatus IN ('Paid','Shipped')
    GROUP BY c.CustomerID, c.FirstName, c.LastName, la.TierLevel
)
SELECT * FROM (
    SELECT 
        CustomerName,
        TierLevel,
        TotalSpent,
        AverageOrderValue,
        TotalTransactions,
        DENSE_RANK() OVER (PARTITION BY TierLevel ORDER BY TotalSpent DESC) as RankInTier
    FROM CustomerMetrics
) AS Ranked
WHERE RankInTier <= 5;

-- 2. Monthly revenue analysis breakdown
-- Business Context: The manager level wants to view total revenue broken down by Product, Subscriptions and Combo for each months

SELECT 
    DATE_FORMAT(o.OrderDate, '%Y-%m') AS SalesMonth,
    SUM(CASE 
        WHEN o.OrderType = 'StandardPurchase' AND oi.ComboID IS NULL 
        THEN oi.UnitPrice * oi.Quantity 
        ELSE 0 
    END) AS ProductRevenue,
    SUM(CASE 
        WHEN o.OrderType = 'StandardPurchase' AND oi.ComboID IS NOT NULL 
        THEN oi.UnitPrice * oi.Quantity 
        ELSE 0 
    END) AS ComboRevenue,
    SUM(CASE 
        WHEN o.OrderType = 'SubscriptionBox' 
        THEN oi.UnitPrice * oi.Quantity 
        ELSE 0 
    END) AS SubscriptionRevenue,
    COUNT(DISTINCT o.OrderID) as TotalOrders
FROM `Order` o
JOIN OrderItem oi ON o.OrderID = oi.OrderID
WHERE o.OrderStatus != 'Cancelled'
GROUP BY SalesMonth
ORDER BY SalesMonth DESC;

-- 3. Inventory Alert
-- Business Context: Which products have high stock levels but haven't sold a single unit in the last 30 days? 

SELECT 
    p.ProductName,
    p.SKU,
    i.QuantityOnHand,
    pc.CategoryName
FROM Product p
JOIN Inventory i ON p.ProductID = i.ProductID
JOIN ProductCategory pc ON p.CategoryID = pc.CategoryID
WHERE i.QuantityOnHand > 20 -- Assuming 20 units are significant high stock
AND NOT EXISTS (
    -- Subquery: Check if this product appears in any recent order, from 30 days
    SELECT 1 
    FROM OrderItem oi
    JOIN `Order` o ON oi.OrderID = o.OrderID
    WHERE oi.ProductID = p.ProductID
    AND o.OrderDate >= DATE_SUB('2024-12-30', INTERVAL 30 DAY) -- 30 Dec 2024 is the latest order date in the sample data
)
ORDER BY i.QuantityOnHand DESC;

-- 4. High-value combo performance
-- Business Context: Which "Combo" bundles are generating high revenue and have high timesold

SELECT 
    cp.ComboName,
    COUNT(oi.OrderItemID) as TimesSold,
    SUM(oi.UnitPrice * oi.Quantity) as TotalRevenue
FROM ComboProduct cp
JOIN OrderItem oi ON cp.ComboID = oi.ComboID
GROUP BY cp.ComboName
HAVING TotalRevenue > 200  -- Filter Combo with more than 200 pounds revenue
ORDER BY TotalRevenue DESC;

-- 5. Delivery performance gap
-- Business Context: Are we delivering on time? Calculating the average delay (in days) per Delivery Zone to see which regions are struggling

SELECT 
    dz.ZoneName,
    COUNT(d.DeliveryID) as TotalDeliveries,
    -- Calculate difference between Actual and Scheduled
    AVG(DATEDIFF(d.ActualDeliveryDate, d.ScheduledDeliveryDate)) AS AvgDelayDays,
    SUM(CASE WHEN d.DeliveryStatus = 'Failed' THEN 1 ELSE 0 END) as FailedCount
FROM Delivery d
JOIN DeliveryZone dz ON d.ZoneID = dz.ZoneID
WHERE d.ActualDeliveryDate IS NOT NULL
GROUP BY dz.ZoneName
ORDER BY AvgDelayDays DESC;

-- 6. Customer retention & Churn risk 
-- Business Context: Analyzing how many days pass between our customer orders? If the gap is growing, they might be about to leave.
WITH CustomerActivity AS (
    SELECT 
        c.CustomerID,
        CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
        MAX(o.OrderDate) AS LastOrderDate,
        COUNT(o.OrderID) AS TotalOrders,
        DATEDIFF('2024-12-30', MAX(o.OrderDate)) AS DaysSinceLastOrder, -- 30 Dec 2024 is the latest order date in the sample data
        la.TierLevel
    FROM Customer c
    JOIN `Order` o ON c.CustomerID = o.CustomerID
    LEFT JOIN LoyaltyAccount la ON c.CustomerID = la.CustomerID
    GROUP BY c.CustomerID, c.FirstName, c.LastName, la.TierLevel
)
SELECT 
    CustomerName,
    TierLevel,
    LastOrderDate,
    DaysSinceLastOrder,
    TotalOrders,
    CASE 
        WHEN DaysSinceLastOrder >= 60 THEN 'High Risk'
        When DaysSinceLastOrder >= 40 THEN 'Medium Risk'
        ELSE 'Active'
    END AS ChurnRiskLevel
FROM CustomerActivity
WHERE DaysSinceLastOrder >= 20  -- Focus on at-risk customers
ORDER BY DaysSinceLastOrder DESC;

-- 7. Product Profitability Report
-- Business Context: Which products have the highest profit margin? We need to prioritize selling high-margin items.

SELECT 
    p.ProductName,
    p.UnitPrice,
    p.CostPrice,
    -- Calculate Margin
    (p.UnitPrice - p.CostPrice) as ProfitPerUnit,
    -- Calculate Margin Percentage
    ROUND(((p.UnitPrice - p.CostPrice) / p.UnitPrice * 100), 2) as MarginPercentage,
    pc.CategoryName
FROM Product p
JOIN ProductCategory pc ON p.CategoryID = pc.CategoryID
ORDER BY MarginPercentage DESC
LIMIT 10;

-- 8. Analyzing big spender behavior
-- Business Context: Find customers who have placed an order larger than the average order value of the entire store. These are upsell targets.

SELECT 
    o.OrderID,
    CONCAT(c.FirstName, ' ', c.LastName) as Customer,
    o.TotalAmount,
    ROUND((SELECT AVG(TotalAmount) FROM `Order`), 2) as AverageOrderValue -- Scalar Subquery
FROM `Order` o
JOIN Customer c ON o.CustomerID = c.CustomerID
WHERE o.TotalAmount > (SELECT AVG(TotalAmount) FROM `Order`) * 1.5 -- 50% higher than average
ORDER BY o.TotalAmount DESC;

-- 9. Subscription Cohort Analysis
-- Business Context: Track monthly subscription cohorts to measure retention over time

SELECT 
    DATE_FORMAT(StartDate, '%Y-%m') AS CohortMonth,
    COUNT(DISTINCT SubscriptionID) AS InitialSubscribers,
    SUM(CASE WHEN SubscriptionStatus = 'Active' THEN 1 ELSE 0 END) AS StillActive,
    ROUND(SUM(CASE WHEN SubscriptionStatus = 'Active' THEN 1 ELSE 0 END) * 100.0 / 
          COUNT(DISTINCT SubscriptionID), 2) AS RetentionRate,
    AVG(DATEDIFF(COALESCE(CancellationDate, '2024-12-30'), StartDate)) AS AvgLifetimeDays
FROM Subscription
GROUP BY CohortMonth
ORDER BY CohortMonth DESC;
