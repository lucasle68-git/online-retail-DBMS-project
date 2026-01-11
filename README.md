# Database Management System for Online Retail

A comprehensive MySQL database system designed for **The Gentleman's Hub** - a men's grooming and wardrobe e-commerce platform with multi-channel operations including online retail, subscription boxes, and loyalty programs.

## Table of Contents
- [Overview](#overview)
- [Business Context](#business-context)
- [Database Architecture](#database-architecture)
- [Entity Relationship Diagrams](#entity-relationship-diagrams)
- [Key Features](#key-features)
- [Technical Implementation](#technical-implementation)
- [Advanced SQL Queries](#advanced-sql-queries)
- [Security Implementation](#security-implementation)
- [Performance Optimization](#performance-optimization)
- [Installation Guide](#installation-guide)
- [Technologies Used](#technologies-used)

## Overview

This project implements a production-ready relational database system that addresses critical data management challenges in e-commerce operations:

- **Data Silos**: Unified star schema integrating 3 revenue channels
- **Data Redundancy**: 3NF normalization eliminating update anomalies
- **Regulatory Compliance**: GDPR consent tracking & PCI-DSS payment security
- **Access Control**: Role-Based Access Control (RBAC) with masked views

## Business Context

**The Gentleman's Hub** operates through three integrated revenue channels:
1. **Online Retail** - Standard product purchases
2. **Subscription Boxes** - Monthly grooming/wardrobe boxes
3. **Loyalty Programme** - Points-based rewards system (Bronze/Silver/Gold tiers)

### Stakeholder Structure
| Role | Access Level | Description |
|------|--------------|-------------|
| C-Level Management | Full Admin | Strategic oversight, compliance audits |
| Department Heads (5) | Domain-Specific | Finance, Marketing, Customer Service, Warehouse, Product |
| Operational Staff | Restricted | Daily task execution |
| External (Customers) | Minimal | Transactional access only |

## Database Architecture

### Star Schema Design
The database comprises **18 entities** organized into two integrated systems:

**Core Transaction Flow (12 entities)**
- Customer Domain: `Customer`, `Address`, `ConsentRecord`
- Product Domain: `Product`, `ProductCategory`, `ComboProduct`, `ComboProductItem`
- Transaction Domain: `Order`, `OrderItem`, `Payment`, `Delivery`, `DeliveryZone`

**Supporting Systems (6 entities)**
- Loyalty: `LoyaltyAccount`, `LoyaltyTransaction`
- Subscription: `Subscription`
- Inventory: `Inventory`
- Promotions: `Coupon`, `ReturnRequest`

## Entity Relationship Diagrams
### Core Transaction Flow
![20A54EBF-370D-4522-B388-D77DECDC6A41_1_105_c](https://github.com/user-attachments/assets/88def324-bbf0-4b64-a562-3a346b718df4)

### Supporting Systems
![815E1E1D-A7B1-4077-8544-F4F1E2AB8DB0_1_105_c](https://github.com/user-attachments/assets/42aed769-b2d9-4b1d-a01f-cd8492126f89)

## Key Features

### Security & Compliance
- **PCI-DSS Compliant Payment Processing**: Card tokenization, no CVV storage
- **GDPR Consent Tracking**: Granular consent per channel (Website, Email, Mobile)
- **Role-Based Access Control**: 5 department-specific access levels
- **Masked Views**: Sensitive data protection for non-authorized roles

### Business Intelligence Ready
- Pre-built analytical queries for:
  - Customer segmentation (RFM Analysis)
  - Revenue breakdown by channel
  - Churn risk prediction
  - Inventory alerts
  - Delivery performance metrics

### Performance Optimized
- Composite indexes on high-frequency JOIN operations
- 25% query performance improvement demonstrated
- Strategic denormalization for historical pricing

## Technical Implementation

### Normalization Strategy

| Form | Implementation | Example |
|------|----------------|---------|
| **1NF** | Atomic values, no repeating groups | ConsentRecord stores each consent type as individual rows |
| **2NF** | Eliminated partial dependencies | OrderItem references ProductID, not ProductName |
| **3NF** | Removed transitive dependencies | Product references CategoryID, not CategoryName |

### Justified Denormalization
- `OrderItem.UnitPrice`: Preserves historical pricing (prevents audit issues when prices change)
- `Order.TaxAmount/ShippingFee`: Immutable for accounting compliance

### Data Types & Constraints

```sql
-- Monetary precision (avoids floating-point errors)
DECIMAL(10,2) for all price fields

-- ENUM for controlled vocabularies (1 byte vs VARCHAR)
ENUM('Pending','Paid','Shipped','Cancelled','Delivered') for OrderStatus

-- CHECK constraints for data validation
CardExpiryMonth CHECK (BETWEEN 1 AND 12)
CHECK (ComboPrice < StandardPrice)
```

## Advanced SQL Queries

The project includes **9 business intelligence queries**:

| # | Query | Technique | Business Purpose |
|---|-------|-----------|------------------|
| 1 | Top Customer Spending | CTE + DENSE_RANK() | VIP identification per loyalty tier |
| 2 | Monthly Revenue Breakdown | CASE + Aggregation | Channel performance analysis |
| 3 | Inventory Alert | NOT EXISTS Subquery | Overstock identification |
| 4 | Combo Performance | GROUP BY + HAVING | Bundle optimization |
| 5 | Delivery Gap Analysis | DATEDIFF() | SLA monitoring by zone |
| 6 | Churn Risk Detection | LAG() Window Function | Customer retention |
| 7 | Product Profitability | Margin Calculation | Pricing strategy |
| 8 | Big Spender Analysis | Scalar Subquery | Upsell targeting |
| 9 | Subscription Cohorts | COALESCE + Grouping | Retention metrics |

### Example: Churn Risk Detection

```sql
WITH CustomerActivity AS (
    SELECT 
        c.CustomerID,
        CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
        MAX(o.OrderDate) AS LastOrderDate,
        DATEDIFF(CURDATE(), MAX(o.OrderDate)) AS DaysSinceLastOrder,
        la.TierLevel
    FROM Customer c
    JOIN `Order` o ON c.CustomerID = o.CustomerID
    LEFT JOIN LoyaltyAccount la ON c.CustomerID = la.CustomerID
    GROUP BY c.CustomerID, c.FirstName, c.LastName, la.TierLevel
)
SELECT 
    CustomerName, TierLevel, DaysSinceLastOrder,
    CASE 
        WHEN DaysSinceLastOrder >= 60 THEN 'High Risk'
        WHEN DaysSinceLastOrder >= 40 THEN 'Medium Risk'
        ELSE 'Active'
    END AS ChurnRiskLevel
FROM CustomerActivity
WHERE DaysSinceLastOrder >= 20
ORDER BY DaysSinceLastOrder DESC;
```

## Security Implementation

### User Roles & Permissions

```sql
-- Example: Marketing Head (masked view access only)
CREATE USER 'marketing_head'@'localhost' IDENTIFIED BY 'SecureMK2024!';
GRANT SELECT ON CustomerPaymentMasked TO 'marketing_head'@'localhost';
GRANT SELECT ON ProductPublic TO 'marketing_head'@'localhost';
-- NO direct access to Payment or Product tables
```

### Masked Views

```sql
-- PCI-DSS Compliant Payment View
CREATE VIEW CustomerPaymentMasked AS
SELECT 
    BillingID,
    PaymentDate,
    CONCAT('****-****-****-', CardLastFour) AS MaskedCardNumber,
    CardBrand,
    NULL AS CardToken  -- COMPLETELY HIDDEN
FROM Payment;

-- Public Product View (hides cost data)
CREATE VIEW ProductPublic AS
SELECT 
    ProductID, ProductName, SKU, UnitPrice,
    NULL AS CostPrice  -- COMPLETELY HIDDEN
FROM Product;
```

### Access Matrix

| Role | Payment | Product | Customer | Orders |
|------|---------|---------|----------|--------|
| Finance Head | Full | Full | SELECT | SELECT |
| Marketing Head | Masked | Masked | SELECT | SELECT |
| Customer Service | Masked | Masked | SELECT | SELECT/UPDATE |
| Warehouse Head | None | Masked | None | SELECT |
| Product Head | None | Full (excl. CostPrice UPDATE) | None | SELECT |

## Performance Optimization

### Indexing Strategy

```sql
-- Composite indexes for frequent JOINs
CREATE INDEX idx_order_customer ON `Order`(CustomerID, OrderDate);
CREATE INDEX idx_orderitem_product ON OrderItem(ProductID, OrderID);
CREATE INDEX idx_loyalty_customer ON LoyaltyAccount(CustomerID, TierLevel);
CREATE INDEX idx_delivery_zone ON Delivery(ZoneID, DeliveryStatus);
```

### Performance Results

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Access Type | ALL (Full Scan) | ref (Index Lookup) | ✅ |
| Rows Examined | 120 | 2 | 98% reduction |
| Query Time | 0.0010s | 0.00081s | 25% faster |

## Installation Guide

### Prerequisites
- MySQL 8.0+
- MySQL Workbench (recommended)

### Setup Steps

```bash
# 1. Clone repository
git clone https://github.com/lucasle68-git/online-retail-DBMS-project.git
cd online-retail-DBMS-project

# 2. Create database and schema
mysql -u root -p < sql/01_schema.sql

# 3. Load sample data
mysql -u root -p < sql/02_sample_data.sql

# 4. Apply security & optimization
mysql -u root -p < sql/03_security_optimization.sql
```

### File Structure
```
database-management-retail/
├── README.md
├── sql/
│   ├── 01_schema.sql          # Database schema (18 tables) & Advanced query for analytics
│   ├── 02_sample_data.sql     # Sample data (~50+ rows/table)
│   └── 03_security_optimization.sql  # RBAC & indexes
├── docs/
│   └── data_dictionary.md     # Complete column documentation
```

## Technologies Used

| Technology | Purpose |
|------------|---------|
| ![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?logo=mysql&logoColor=white) | Relational Database (InnoDB engine) |
| ![SQL](https://img.shields.io/badge/SQL-Advanced-orange) | CTEs, Window Functions, Subqueries |

## Key Learnings

- **Star Schema Design**: Optimizing for analytical queries while maintaining transactional integrity
- **3NF vs Denormalization**: Balancing normalization with practical requirements (historical pricing)
- **Security by Design**: Implementing least-privilege access with masked views
- **Performance Tuning**: Strategic indexing based on query patterns

## Future Enhancements

- [ ] Integration with Apache Airflow for automated reporting
- [ ] Machine Learning for dynamic delivery predictions
- [ ] Real-time inventory alerts via Slack/Teams integration
- [ ] Data warehouse layer for advanced analytics

---

## Contact

**Lucas Le** - MSc Business Analytics @ University of Glasgow

Glasgow, Scotland  
luong.ldd.work@gmail.com  
[LinkedIn](https://www.linkedin.com/in/lucasle68/)

---

*This project was developed as part of MGT5492 - Data Management & Engineering coursework.*
