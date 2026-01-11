-- CREATE DATABASE
CREATE DATABASE IF NOT EXISTS gentlemans_hub_db
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;
USE gentlemans_hub_db;

-- Table 1: Order (Star Schema Fact Table)
-- Central transaction hub connecting Customer, Payment, Coupon dimensions

CREATE TABLE `Order` (
    OrderID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    BillingID INT NOT NULL,
    CouponID INT,
    OrderDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    OrderType ENUM('StandardPurchase','SubscriptionBox','LoyaltyRedemption','GiftPurchase') NOT NULL, # ENUM to restrict the data entry error
    OrderStatus ENUM('Pending','Paid','Shipped','Cancelled','Delivered') DEFAULT 'Pending',
    TaxAmount DECIMAL(10,2) DEFAULT 0.00,
    ShippingFee DECIMAL(10,2) DEFAULT 0.00,
    PaymentStatus ENUM('Authorized','Captured','Failed') DEFAULT 'Authorized',
    TotalAmount DECIMAL(10,2) NOT NULL CHECK (TotalAmount >= 0),
    INDEX idx_customer_date (CustomerID, OrderDate), # INDEX To create internal lookup list, faster search
    INDEX idx_status (OrderStatus),
    INDEX idx_type (OrderType),
    INDEX idx_order_date (OrderDate)
) ENGINE=InnoDB COMMENT='Star schema fact table - transaction hub';

-- Table 2: OrderItem (Junction Table - Order Line Items)
CREATE TABLE OrderItem (
    OrderItemID INT AUTO_INCREMENT PRIMARY KEY,
    OrderID INT NOT NULL,
    ComboID INT,
    ProductID INT,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (OrderID) REFERENCES `Order`(OrderID) ON DELETE CASCADE,
    CHECK ((ProductID IS NOT NULL AND ComboID IS NULL) OR (ProductID IS NULL AND ComboID IS NOT NULL)), # Remove duplicated data
    INDEX idx_order (OrderID),
    INDEX idx_product (ProductID),
    INDEX idx_combo (ComboID)
) ENGINE=InnoDB COMMENT='Order line items - fact-dimension junction';


-- Customer Domain
-- Table 3: Customer Dimension
CREATE TABLE Customer (
    CustomerID INT AUTO_INCREMENT PRIMARY KEY,
    FirstName VARCHAR(100) NOT NULL,
    LastName VARCHAR(100) NOT NULL,
    Email VARCHAR(255) NOT NULL UNIQUE,
    PhoneNumber VARCHAR(20),
    DOB DATE,
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    LastUpdated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_email (Email),
    INDEX idx_lastname (LastName),
    INDEX idx_created (CreatedDate)
) ENGINE=InnoDB COMMENT='Master customer profiles - star schema dimension';

-- Table 4: Address
CREATE TABLE Address (
    AddressID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    AddressLine VARCHAR(200) NOT NULL,
    City VARCHAR(100) NOT NULL,
    Postcode VARCHAR(10) NOT NULL,
    Country VARCHAR(50) DEFAULT 'United Kingdom',
    IsDefault BOOLEAN DEFAULT 0,
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    INDEX idx_customer (CustomerID),
    INDEX idx_postcode (Postcode)
) ENGINE=InnoDB COMMENT='Normalized customer addresses';

-- Product Domain
-- Table 5: ProductCategory 
CREATE TABLE ProductCategory (
    CategoryID INT AUTO_INCREMENT PRIMARY KEY,
    ParentCategoryID INT,
    CategoryName VARCHAR(100) NOT NULL,
    Description VARCHAR(200),
    IsActive BOOLEAN DEFAULT 1,
    FOREIGN KEY (ParentCategoryID) REFERENCES ProductCategory(CategoryID) ON DELETE SET NULL,
    INDEX idx_parent (ParentCategoryID),
    INDEX idx_active (IsActive)
) ENGINE=InnoDB COMMENT='Product category hierarchy';

-- Table 6: Product
CREATE TABLE Product (
    ProductID INT AUTO_INCREMENT PRIMARY KEY,
    CategoryID INT NOT NULL,
    ProductName VARCHAR(100) NOT NULL,
    ProductDescription VARCHAR(200),
    UnitPrice DECIMAL(10,2) NOT NULL CHECK (UnitPrice > 0),
    CostPrice DECIMAL(10,2) CHECK (CostPrice >= 0),
    SKU VARCHAR(50) NOT NULL UNIQUE,
    IsActive BOOLEAN DEFAULT 1,
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CategoryID) REFERENCES ProductCategory(CategoryID) ON DELETE RESTRICT,
    INDEX idx_category (CategoryID),
    INDEX idx_sku (SKU),
    INDEX idx_active (IsActive)
) ENGINE=InnoDB COMMENT='Product catalog - star schema dimension';

-- Table 7: ComboProduct 
CREATE TABLE ComboProduct (
    ComboID INT AUTO_INCREMENT PRIMARY KEY,
    ComboName VARCHAR(100) NOT NULL,
    ComboDescription VARCHAR(200),
    StandardPrice DECIMAL(10,2) NOT NULL,
    ComboPrice DECIMAL(10,2) NOT NULL,
    IsActive BOOLEAN DEFAULT 1,
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    CHECK (ComboPrice < StandardPrice),
    CHECK (ComboPrice > 0),
    INDEX idx_active (IsActive)
) ENGINE=InnoDB COMMENT='Bundled product offerings';

-- Table 8: ComboProductItem
CREATE TABLE ComboProductItem (
    ComboItemID INT AUTO_INCREMENT PRIMARY KEY,
    ComboID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    IsSubstitutable BOOLEAN DEFAULT 0,
    FOREIGN KEY (ComboID) REFERENCES ComboProduct(ComboID) ON DELETE CASCADE,
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID) ON DELETE RESTRICT,
    UNIQUE KEY unique_combo_product (ComboID, ProductID),
    INDEX idx_combo (ComboID),
    INDEX idx_product (ProductID)
) ENGINE=InnoDB COMMENT='Combo contents - junction table';

-- Payment Domain
-- Table 9: Payment (PCI-DSS Compliant Payment Processing)
CREATE TABLE Payment (
    BillingID INT AUTO_INCREMENT PRIMARY KEY,
    PaymentDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    PaymentType VARCHAR(20) NOT NULL,
    PaymentMethodType ENUM('Visa','Mastercard','Amex','PayPal','ApplePay') NOT NULL,
    CardToken VARCHAR(255),
    CardLastFour VARCHAR(4),
    CardBrand VARCHAR(50),
    CardExpiryMonth INT CHECK (CardExpiryMonth BETWEEN 1 AND 12),
    CardExpiryYear INT CHECK (CardExpiryYear >= 2025),
    TransactionReference VARCHAR(100),
    PaymentStatus ENUM('Pending','Authorized','Captured','Failed','Refunded') DEFAULT 'Pending',
    INDEX idx_date (PaymentDate),
    INDEX idx_status (PaymentStatus)
) ENGINE=InnoDB COMMENT='Payment processing - PCI-DSS compliant';

-- Delivery Domain
-- Table 10: DeliveryZone
CREATE TABLE DeliveryZone (
    ZoneID INT AUTO_INCREMENT PRIMARY KEY,
    ZoneName VARCHAR(100) NOT NULL,
    StandardDeliveryDays INT NOT NULL DEFAULT 3,
    MaxDailyCapacity INT NOT NULL,
    PostcodePrefixes VARCHAR(255) NOT NULL,
    IsActive BOOLEAN DEFAULT 1,
    INDEX idx_active (IsActive)
) ENGINE=InnoDB COMMENT='UK delivery zones - capacity management';

-- Table 11: Delivery (Delivery Tracking)
CREATE TABLE Delivery (
    DeliveryID INT AUTO_INCREMENT PRIMARY KEY,
    OrderID INT NOT NULL UNIQUE,
    ZoneID INT NOT NULL,
    ScheduledDeliveryDate DATE NOT NULL,
    ScheduledTimeSlot VARCHAR(50),
    ActualDeliveryDate DATETIME,
    DeliveryStatus ENUM('Processing','InTransit','Delivered','Failed') DEFAULT 'Processing',
    TrackingNumber VARCHAR(100) UNIQUE,
    FOREIGN KEY (OrderID) REFERENCES `Order`(OrderID) ON DELETE CASCADE,
    FOREIGN KEY (ZoneID) REFERENCES DeliveryZone(ZoneID) ON DELETE RESTRICT,
    INDEX idx_order (OrderID),
    INDEX idx_zone (ZoneID),
    INDEX idx_status (DeliveryStatus),
    INDEX idx_scheduled_date (ScheduledDeliveryDate)
) ENGINE=InnoDB COMMENT='Delivery tracking';

-- Phase 2: Supporting Systems

-- Loyalty Domain
-- Table 12: LoyaltyAccount 
CREATE TABLE LoyaltyAccount (
    LoyaltyAccountID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    CurrentPointsBalance INT DEFAULT 0,
    TotalPointsEarned INT DEFAULT 0,
    TierLevel VARCHAR(20) DEFAULT 'Bronze',
    IsActive BOOLEAN DEFAULT 1,
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    INDEX idx_customer (CustomerID),
    INDEX idx_tier (TierLevel),
    INDEX idx_active (IsActive)
) ENGINE=InnoDB COMMENT='Customer loyalty profiles';

-- Table 13: LoyaltyTransactions 
CREATE TABLE LoyaltyTransaction (
    TransactionID INT AUTO_INCREMENT PRIMARY KEY,
    LoyaltyAccountID INT NOT NULL,
    OrderID INT,
    TotalPointsEarned INT NOT NULL,
    TierLevel ENUM('Bronze','Silver','Gold') NOT NULL,
    IsActive BOOLEAN DEFAULT 1,
    TransactionDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (LoyaltyAccountID) REFERENCES LoyaltyAccount(LoyaltyAccountID) ON DELETE CASCADE,
    FOREIGN KEY (OrderID) REFERENCES `Order`(OrderID) ON DELETE SET NULL,
    INDEX idx_account (LoyaltyAccountID),
    INDEX idx_order (OrderID),
    INDEX idx_date (TransactionDate)
) ENGINE=InnoDB COMMENT='Loyalty point transaction history';

-- Subscription System
-- Table 14: Subscription 
CREATE TABLE Subscription (
    SubscriptionID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    ProductID INT,
    ComboID INT,
    StartDate DATE NOT NULL,
    CancellationDate DATE,
    CancellationReason VARCHAR(255),
    SubscriptionStatus ENUM('Active','Paused','Cancelled') DEFAULT 'Active',
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID) ON DELETE RESTRICT,
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID) ON DELETE RESTRICT,
    FOREIGN KEY (ComboID) REFERENCES ComboProduct(ComboID) ON DELETE RESTRICT,
    CHECK ((ProductID IS NOT NULL AND ComboID IS NULL) OR (ProductID IS NULL AND ComboID IS NOT NULL)),
    INDEX idx_customer (CustomerID),
    INDEX idx_product (ProductID),
    INDEX idx_combo (ComboID),
    INDEX idx_status (SubscriptionStatus),
    INDEX idx_start_date (StartDate)
) ENGINE=InnoDB COMMENT='Subscription management';

-- Inventory Management
-- Table 15: Inventory
CREATE TABLE Inventory (
    InventoryID INT AUTO_INCREMENT PRIMARY KEY,
    ProductID INT NOT NULL,
    LocationName VARCHAR(100) NOT NULL,
    LocationPostcode VARCHAR(10) NOT NULL,
    QuantityOnHand INT DEFAULT 0,
    QuantityReserved INT DEFAULT 1,
    QuantityAvailable INT AS (QuantityOnHand - QuantityReserved) STORED,
    ReorderPoint INT DEFAULT 10,
    LastStockCheck DATETIME,
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID) ON DELETE CASCADE,
    INDEX idx_product (ProductID),
    INDEX idx_location (LocationName),
    INDEX idx_available (QuantityAvailable)
) ENGINE=InnoDB COMMENT='Product inventory by location';

-- Order Support Systems
-- Table 16: ReturnRequest
CREATE TABLE ReturnRequest (
    ReturnID INT AUTO_INCREMENT PRIMARY KEY,
    OrderID INT NOT NULL,
    RequestDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    CompletedDate DATETIME,
    ReturnMethod ENUM('Dropoff','Pickup','Mail') NOT NULL,
    ReturnReason VARCHAR(255),
    ReturnStatus ENUM('Requested','Approved','Refunded') DEFAULT 'Requested',
    FOREIGN KEY (OrderID) REFERENCES `Order`(OrderID) ON DELETE CASCADE,
    INDEX idx_order (OrderID),
    INDEX idx_status (ReturnStatus),
    INDEX idx_request_date (RequestDate)
) ENGINE=InnoDB COMMENT='Product return requests';

-- Table 17: Coupon (Discount Codes)
CREATE TABLE Coupon (
    CouponID INT AUTO_INCREMENT PRIMARY KEY,
    Code VARCHAR(20) NOT NULL UNIQUE,
    Description VARCHAR(200),
    DiscountType ENUM('Percent','FixedAmount') NOT NULL,
    DiscountValue DECIMAL(10,2) NOT NULL,
    MinOrderValue DECIMAL(10,2) DEFAULT 0.00,
    UsageLimit INT,
    UsageCount INT DEFAULT 0,
    IsActive BOOLEAN DEFAULT 1,
    CreatedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_code (Code),
    INDEX idx_active (IsActive)
) ENGINE=InnoDB COMMENT='Promotional discount codes';

-- Table 18: ConsentRecord
CREATE TABLE ConsentRecord (
    ConsentID INT AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    ConsentType ENUM('Marketing','Cookies','Terms') NOT NULL,
    ConsentGiven BOOLEAN NOT NULL DEFAULT 0,
    ConsentDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID) ON DELETE CASCADE,
    INDEX idx_customer (CustomerID),
    INDEX idx_type (ConsentType),
    INDEX idx_date (ConsentDate)
) ENGINE=InnoDB COMMENT='GDPR consent tracking across channels';


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


