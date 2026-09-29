-- 03_indexing_and_performance.sql
-- Measures the effect of a composite index on a frequent Customer-Order join.
-- Run after 01 and 02. Numbers depend on your machine and data volume, so record your own results in the README.

USE gentlemans_hub_db;

-- The schema already creates idx_customer_date (CustomerID, OrderDate) on `Order`.
-- To measure a fair baseline, drop it first, test, then add it back.

-- Step 1: baseline without the composite index
ALTER TABLE `Order` DROP INDEX idx_customer_date;

EXPLAIN ANALYZE
SELECT c.CustomerID, SUM(o.TotalAmount) AS TotalSpent
FROM Customer c
JOIN `Order` o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID;

-- Step 2: add the composite index back and re-test
CREATE INDEX idx_customer_date ON `Order`(CustomerID, OrderDate);

EXPLAIN ANALYZE
SELECT c.CustomerID, SUM(o.TotalAmount) AS TotalSpent
FROM Customer c
JOIN `Order` o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID;

-- Step 3: additional composite indexes for other frequent joins and filters
CREATE INDEX idx_orderitem_product ON OrderItem(ProductID, OrderID);
CREATE INDEX idx_loyalty_customer ON LoyaltyAccount(CustomerID, TierLevel);
CREATE INDEX idx_delivery_zone ON Delivery(ZoneID, DeliveryStatus);
