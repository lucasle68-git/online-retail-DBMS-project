-- ADVANCED QUERY

Use gentlemans_hub_db;
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
    AND o.OrderDate >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
);

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
        DATEDIFF('2024-12-30', MAX(o.OrderDate)) AS DaysSinceLastOrder, # 30 Dec 2024 is the lastest order of the dataset
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
    (SELECT AVG(TotalAmount) FROM `Order`) as AverageOrderStandard -- Scalar Subquery
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

-- OPTIMISATION QUERY
EXPLAIN SELECT c.CustomerID, SUM(o.TotalAmount) 
FROM Customer c 
JOIN `Order` o ON c.CustomerID = o.CustomerID 
GROUP BY c.CustomerID;

-- Create composite indexes on frequently joined columns
CREATE INDEX idx_order_customer ON `Order`(CustomerID, OrderDate);
CREATE INDEX idx_orderitem_product ON OrderItem(ProductID, OrderID);
CREATE INDEX idx_loyalty_customer ON LoyaltyAccount(CustomerID, TierLevel);
CREATE INDEX idx_delivery_zone ON Delivery(ZoneID, DeliveryStatus);


-- SECURITY
-- STEP 1: CREATE DEPARTMENT HEAD USERS (PASSWORD-PROTECTED)

-- Warehouse Head: Supply chain and fulfillment
CREATE USER IF NOT EXISTS 'warehouse_head'@'localhost' IDENTIFIED BY 'SecureWH2024!';
GRANT SELECT, UPDATE ON gentlemans_hub_db.Inventory TO 'warehouse_head'@'localhost';
GRANT SELECT, UPDATE ON gentlemans_hub_db.OrderItem TO 'warehouse_head'@'localhost';
GRANT SELECT, UPDATE ON gentlemans_hub_db.Delivery TO 'warehouse_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.DeliveryZone TO 'warehouse_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.`Order` TO 'warehouse_head'@'localhost';

-- Customer Service Head: Order and return management
CREATE USER IF NOT EXISTS 'customer_service_head'@'localhost' IDENTIFIED BY 'SecureCS2024!';
GRANT SELECT ON gentlemans_hub_db.Customer TO 'customer_service_head'@'localhost';
GRANT SELECT, UPDATE ON gentlemans_hub_db.`Order` TO 'customer_service_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.OrderItem TO 'customer_service_head'@'localhost';
GRANT SELECT, INSERT, UPDATE ON gentlemans_hub_db.ReturnRequest TO 'customer_service_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Address TO 'customer_service_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Delivery TO 'customer_service_head'@'localhost';

-- Finance Head: Payment reconciliation and compliance
CREATE USER IF NOT EXISTS 'finance_head'@'localhost' IDENTIFIED BY 'SecureFN2024!';
GRANT SELECT ON gentlemans_hub_db.Payment TO 'finance_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.`Order` TO 'finance_head'@'localhost';
GRANT SELECT, UPDATE ON gentlemans_hub_db.Subscription TO 'finance_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Customer TO 'finance_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Coupon TO 'finance_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.LoyaltyTransaction TO 'finance_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Product TO 'finance_head'@'localhost';
-- Finance Head gets full Payment and Product access (including CardToken and CostPrice)

-- Product Head: Catalogue and inventory planning
CREATE USER IF NOT EXISTS 'product_head'@'localhost' IDENTIFIED BY 'SecurePD2024!';
GRANT SELECT, INSERT, UPDATE ON gentlemans_hub_db.Product TO 'product_head'@'localhost';
GRANT SELECT, INSERT, UPDATE ON gentlemans_hub_db.ProductCategory TO 'product_head'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON gentlemans_hub_db.ComboProduct TO 'product_head'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON gentlemans_hub_db.ComboProductItem TO 'product_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Inventory TO 'product_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.OrderItem TO 'product_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.ReturnRequest TO 'product_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.`Order` TO 'product_head'@'localhost';

-- Marketing Head: Customer analytics and campaigns
CREATE USER IF NOT EXISTS 'marketing_head'@'localhost' IDENTIFIED BY 'SecureMK2024!';
GRANT SELECT ON gentlemans_hub_db.Customer TO 'marketing_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.`Order` TO 'marketing_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.OrderItem TO 'marketing_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.LoyaltyAccount TO 'marketing_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.LoyaltyTransaction TO 'marketing_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.Subscription TO 'marketing_head'@'localhost';
GRANT SELECT, UPDATE ON gentlemans_hub_db.Coupon TO 'marketing_head'@'localhost';
GRANT SELECT ON gentlemans_hub_db.ConsentRecord TO 'marketing_head'@'localhost';

SELECT 'STEP 1 COMPLETE: 5 Department Head users created' AS Status;


-- STEP 2: CREATE SENSITIVE DATA PROTECTION VIEWS

-- View 1: Masked Payment Data (PCI-DSS Compliance)
DROP VIEW IF EXISTS CustomerPaymentMasked;
CREATE VIEW CustomerPaymentMasked AS
SELECT 
    BillingID,
    PaymentDate,
    PaymentType,
    PaymentMethodType,
    CONCAT('****-****-****-', CardLastFour) AS MaskedCardNumber,
    CardBrand,
    CardExpiryMonth,
    CardExpiryYear,
    TransactionReference,
    PaymentStatus,
    NULL AS CardToken  -- COMPLETELY HIDDEN
FROM Payment;

-- View 2: Public Product Data (Hide Cost Pricing)
DROP VIEW IF EXISTS ProductPublic;
CREATE VIEW ProductPublic AS
SELECT 
    ProductID,
    ProductName,
    SKU,
    CategoryID,
    UnitPrice,
    IsActive,
    NULL AS CostPrice  -- COMPLETELY HIDDEN
FROM Product;

SELECT 'STEP 2 COMPLETE: Masked views created' AS Status;

-- STEP 3: GRANT ACCESS TO MASKED VIEWS (Customer Service & Marketing)

-- Customer Service: Grant masked payment view (no direct Payment access)
GRANT SELECT ON gentlemans_hub_db.CustomerPaymentMasked TO 'customer_service_head'@'localhost';

-- Customer Service: Grant public product view (no direct Product access)
GRANT SELECT ON gentlemans_hub_db.ProductPublic TO 'customer_service_head'@'localhost';

-- Marketing: Grant masked payment view (no direct Payment access)
GRANT SELECT ON gentlemans_hub_db.CustomerPaymentMasked TO 'marketing_head'@'localhost';

-- Marketing: Grant public product view (no direct Product access)
GRANT SELECT ON gentlemans_hub_db.ProductPublic TO 'marketing_head'@'localhost';

-- Warehouse: Grant public product view (no need for cost data in fulfillment)
GRANT SELECT ON gentlemans_hub_db.ProductPublic TO 'warehouse_head'@'localhost';

SELECT 'STEP 3 COMPLETE: Masked views granted to appropriate users' AS Status;


-- STEP 4: VERIFY GRANTS

SELECT '=== WAREHOUSE HEAD GRANTS ===' AS Info;
SHOW GRANTS FOR 'warehouse_head'@'localhost';

SELECT '=== CUSTOMER SERVICE HEAD GRANTS ===' AS Info;
SHOW GRANTS FOR 'customer_service_head'@'localhost';

SELECT '=== FINANCE HEAD GRANTS ===' AS Info;
SHOW GRANTS FOR 'finance_head'@'localhost';

SELECT '=== PRODUCT HEAD GRANTS ===' AS Info;
SHOW GRANTS FOR 'product_head'@'localhost';

SELECT '=== MARKETING HEAD GRANTS ===' AS Info;
SHOW GRANTS FOR 'marketing_head'@'localhost';

-- STEP 5: VERIFY VIEWS CREATED

SHOW FULL TABLES WHERE Table_type = 'VIEW';

-- Test masked views return correct structure
SELECT 'CustomerPaymentMasked View Test:' AS Test;
SELECT * FROM CustomerPaymentMasked LIMIT 1;

SELECT 'ProductPublic View Test:' AS Test;
SELECT * FROM ProductPublic LIMIT 1;


-- FINAL STATUS

SELECT 'SECURITY IMPLEMENTATION COMPLETE' AS Status;
SELECT '5 Department Head users created with password protection' AS Feature_1;
SELECT 'Customer Service & Marketing: NO direct Payment/Product access' AS Feature_2;
SELECT 'Customer Service & Marketing: Masked views ONLY' AS Feature_3;
SELECT 'Finance & Product Heads: Full access (including sensitive data)' AS Feature_4;
SELECT 'Warehouse: Public product view only (no cost data)' AS Feature_5;


