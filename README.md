# Online Retail Database: Design, SQL Analytics & Access Control

A normalised MySQL database for **The Gentleman's Hub**, a fictional men's grooming and wardrobe e-commerce business that sells through three channels: online retail, subscription boxes and a loyalty programme.

The project covers the full design of an operational (OLTP) database: business requirements from five departments, a 3NF relational model with 18 tables, nine analytical SQL queries, indexing and role-based access control with masked views.

> Built for the MGT5492 Data Management & Engineering module (MSc Business Analytics, University of Glasgow). The business and all data are synthetic.

## Table of Contents
- [Business Problem](#business-problem)
- [Database Design](#database-design)
- [Entity Relationship Diagrams](#entity-relationship-diagrams)
- [Analytical SQL Queries](#analytical-sql-queries)
- [Access Control & Data Protection](#access-control--data-protection)
- [Indexing & Performance](#indexing--performance)
- [How to Run](#how-to-run)
- [Repository Structure](#repository-structure)
- [Scope & Limitations](#scope--limitations)

## Business Problem

The Gentleman's Hub runs three revenue channels on separate spreadsheets and tools, which causes:

- **Data silos**: no single view of a customer across purchases, subscriptions and loyalty points
- **Redundancy and update anomalies**: the same product and customer details stored in several places
- **Compliance risk**: no record of marketing consent per channel (GDPR) and card data visible to too many staff (PCI-DSS)
- **Uncontrolled access**: every department could see every table

Requirements were gathered from five department heads (Finance, Marketing, Customer Service, Warehouse, Product) and turned into one integrated relational model.

| Role | Access Level | Needs |
|------|--------------|-------|
| C-Level Management | Full admin | Strategic oversight, compliance audits |
| Department Heads (5) | Domain-specific | Reporting and updates for their own area |
| Operational Staff | Restricted | Daily task execution |
| Customers | Minimal | Their own transactions only |

## Database Design

### Normalised relational model (3NF)

**18 tables** in two groups:

**Core transaction flow (12 tables)**
- Customer: `Customer`, `Address`, `ConsentRecord`
- Product: `Product`, `ProductCategory`, `ComboProduct`, `ComboProductItem`
- Transaction: `Order`, `OrderItem`, `Payment`, `Delivery`, `DeliveryZone`

**Supporting systems (6 tables)**
- Loyalty: `LoyaltyAccount`, `LoyaltyTransaction`
- Subscription: `Subscription`
- Inventory: `Inventory`
- Promotions and returns: `Coupon`, `ReturnRequest`

### Normalisation

| Form | Implementation | Example |
|------|----------------|---------|
| **1NF** | Atomic values, no repeating groups | `ConsentRecord` stores each consent type as its own row |
| **2NF** | No partial dependencies | `OrderItem` references `ProductID`, not `ProductName` |
| **3NF** | No transitive dependencies | `Product` references `CategoryID`, not `CategoryName` |

### Justified denormalisation
- `OrderItem.UnitPrice` keeps the price at the time of sale, so historical revenue stays correct when catalogue prices change.
- `Order.TaxAmount` and `Order.ShippingFee` are stored as charged, for accounting audit.

### Data types & constraints

```sql
-- Monetary precision (avoids floating-point errors)
DECIMAL(10,2) for all price fields

-- ENUM for controlled vocabularies
ENUM('Pending','Paid','Shipped','Cancelled','Delivered') for OrderStatus

-- CHECK constraints enforce business rules
CHECK (CardExpiryMonth BETWEEN 1 AND 12)
CHECK (ComboPrice < StandardPrice)
CHECK ((ProductID IS NOT NULL AND ComboID IS NULL) OR (ProductID IS NULL AND ComboID IS NOT NULL))
```

Full column-level documentation is in [`docs/data_dictionary.md`](docs/data_dictionary.md).

## Entity Relationship Diagrams

### Core Transaction Flow
![Core transaction flow ERD](https://github.com/user-attachments/assets/88def324-bbf0-4b64-a562-3a346b718df4)

### Supporting Systems
![Supporting systems ERD](https://github.com/user-attachments/assets/42aed769-b2d9-4b1d-a01f-cd8492126f89)

## Analytical SQL Queries

Nine business questions, each answered with one query in [`sql/02_analytical_queries.sql`](sql/02_analytical_queries.sql):

| # | Business question | Technique | Used by |
|---|-------------------|-----------|---------|
| 1 | Who are the top 5 spenders in each loyalty tier? | CTE + `DENSE_RANK()` | Marketing |
| 2 | How does monthly revenue split across products, combos and subscriptions? | Conditional aggregation | Management |
| 3 | Which products have high stock but no sales in 30 days? | `NOT EXISTS` subquery | Warehouse |
| 4 | Which combo bundles earn more than £200? | `GROUP BY` + `HAVING` | Product |
| 5 | Which delivery zones are late most often? | `DATEDIFF()` | Customer Service |
| 6 | Which customers are at risk of churning? | CTE + recency banding | Marketing |
| 7 | Which products have the highest margin? | Margin calculation | Finance |
| 8 | Which orders are 50% above the average order value? | Scalar subquery | Marketing |
| 9 | How well do subscription cohorts retain? | Cohort grouping + `COALESCE` | Finance |

### Example: churn risk detection

```sql
WITH CustomerActivity AS (
    SELECT
        c.CustomerID,
        CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
        MAX(o.OrderDate) AS LastOrderDate,
        COUNT(o.OrderID) AS TotalOrders,
        DATEDIFF('2024-12-30', MAX(o.OrderDate)) AS DaysSinceLastOrder, -- latest order date in the sample data
        la.TierLevel
    FROM Customer c
    JOIN `Order` o ON c.CustomerID = o.CustomerID
    LEFT JOIN LoyaltyAccount la ON c.CustomerID = la.CustomerID
    GROUP BY c.CustomerID, c.FirstName, c.LastName, la.TierLevel
)
SELECT
    CustomerName, TierLevel, LastOrderDate, DaysSinceLastOrder, TotalOrders,
    CASE
        WHEN DaysSinceLastOrder >= 60 THEN 'High Risk'
        WHEN DaysSinceLastOrder >= 40 THEN 'Medium Risk'
        ELSE 'Active'
    END AS ChurnRiskLevel
FROM CustomerActivity
WHERE DaysSinceLastOrder >= 20
ORDER BY DaysSinceLastOrder DESC;
```

## Access Control & Data Protection

- **Role-based access control (RBAC)**: five department-head users, each granted only the tables they need (least privilege)
- **Masked views**: `CustomerPaymentMasked` shows only the last four card digits; `ProductPublic` hides cost prices
- **PCI-DSS by design**: cards stored as tokens, no CVV stored
- **GDPR**: marketing consent recorded per channel (website, email, mobile) with dates

```sql
CREATE VIEW CustomerPaymentMasked AS
SELECT BillingID, PaymentDate, CardBrand,
       CONCAT('****-****-****-', CardLastFour) AS MaskedCardNumber,
       NULL AS CardToken  -- hidden
FROM Payment;
```

| Role | Payment | Product | Customer | Orders |
|------|---------|---------|----------|--------|
| Finance Head | Full | Full | SELECT | SELECT |
| Marketing Head | Masked | Masked | SELECT | SELECT |
| Customer Service | Masked | Masked | SELECT | SELECT/UPDATE |
| Warehouse Head | None | Masked | None | SELECT |
| Product Head | None | Full | None | SELECT |

Passwords in [`sql/04_security_rbac.sql`](sql/04_security_rbac.sql) are placeholders; set your own before running.

## Indexing & Performance

Composite indexes were added on the most frequent joins and filters: `Order(CustomerID, OrderDate)`, `OrderItem(ProductID, OrderID)`, `LoyaltyAccount(CustomerID, TierLevel)` and `Delivery(ZoneID, DeliveryStatus)`.

[`sql/03_indexing_and_performance.sql`](sql/03_indexing_and_performance.sql) compares the customer-spend query with and without the `Order(CustomerID, OrderDate)` index using `EXPLAIN ANALYZE`:

| | Without index | With index |
|---|---|---|
| Access on `Order` | Full table scan | Index lookup (`idx_customer_date`) |
| Aggregation | Temporary table | Group aggregate, no temporary table |

With only 120 sample orders, timings are too small to be meaningful. The value of the change is the execution plan: the query no longer scans the whole table or builds a temporary table, which matters as order volume grows.

## How to Run

**Requirements:** MySQL 8.0.18+ (for `EXPLAIN ANALYZE`) and MySQL Workbench or the `mysql` command line.

Run the scripts in order:

```bash
git clone https://github.com/lucasle68-git/online-retail-DBMS-project.git
cd online-retail-DBMS-project

mysql -u root -p < sql/01_schema_and_sample_data.sql      # create database, 18 tables, sample data
mysql -u root -p < sql/02_analytical_queries.sql          # 9 business queries
mysql -u root -p < sql/03_indexing_and_performance.sql    # indexes + before/after plans
mysql -u root -p < sql/04_security_rbac.sql               # users, grants, masked views (set passwords first)
```

In MySQL Workbench: open each file with **File → Open SQL Script** and run it with the lightning-bolt icon, in the same order.

## Repository Structure

```
online-retail-DBMS-project/
├── README.md
├── LICENSE
├── sql/
│   ├── 01_schema_and_sample_data.sql     # database, 18 tables, constraints, sample data
│   ├── 02_analytical_queries.sql         # 9 business queries
│   ├── 03_indexing_and_performance.sql   # composite indexes + EXPLAIN ANALYZE
│   └── 04_security_rbac.sql              # users, grants, masked views
└── docs/
    └── data_dictionary.md                # column-level documentation
```

## Scope & Limitations

- This is an **operational (OLTP) database**, optimised for recording transactions correctly. Heavy reporting would normally run on a separate dimensional model (star schema) in a data warehouse.
- The business and all data are synthetic (about 50–120 rows per table), so performance results show changes in execution plans rather than realistic timings.
- Next step: a separate BI project building an ETL pipeline, a star-schema warehouse and Power BI dashboards on real retail data.

## Technologies

| Technology | Purpose |
|------------|---------|
| ![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?logo=mysql&logoColor=white) | Relational database (InnoDB) |
| ![SQL](https://img.shields.io/badge/SQL-Advanced-orange) | CTEs, window functions, subqueries, views, RBAC |

## Key Learnings

- **3NF vs denormalisation**: normalising to remove anomalies, then denormalising only where history or audit requires it
- **Security by design**: least-privilege access and masked views instead of trusting every user with raw tables
- **Performance tuning**: choosing indexes from real query patterns and checking the execution plan, not just timings

## Contact

**Danh Duc Luong (Lucas) Le** · MSc Business Analytics, University of Glasgow
luong.ldd.work@gmail.com · [LinkedIn](https://www.linkedin.com/in/lucasle68/)
