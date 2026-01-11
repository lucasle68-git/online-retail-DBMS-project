USE gentlemans_hub_db;

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

