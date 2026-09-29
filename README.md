# Online Retail Database: Design, SQL Analytics & Access Control

[![SQL scripts test](https://github.com/lucasle68-git/online-retail-DBMS-project/actions/workflows/test-sql.yml/badge.svg)](https://github.com/lucasle68-git/online-retail-DBMS-project/actions/workflows/test-sql.yml)
![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?logo=mysql&logoColor=white)
![SQL](https://img.shields.io/badge/SQL-CTEs%20%7C%20Window%20Functions%20%7C%20RBAC-orange)

## At a Glance

| | |
|---|---|
| **Problem** | A three-channel retailer (online shop, subscription boxes, loyalty programme) had customer data split across tools, duplicated records and no control over who could see card or cost data. |
| **What I built** | A 3NF MySQL database (18 tables) designed from five departments' requirements, 9 analytical queries, composite indexes and role-based access with masked views. |
| **Key results** | 9 business questions answered in SQL (e.g. Premium Grooming Box drives 5× the revenue of any other bundle; 8 customers flagged High churn risk). Indexing replaced a full table scan with index lookups. Card numbers hidden from 4 of 5 department heads and cost prices from 3. |
| **Proof it runs** | Every script is tested automatically on a fresh MySQL 8.0 database by GitHub Actions (badge above). Query outputs are in [`results/`](results/). |
| **Skills** | Data modelling (3NF), SQL (CTEs, window functions, subqueries), query optimisation, data governance (GDPR, PCI-DSS, RBAC), documentation |

A normalised MySQL database for **The Gentleman's Hub**, a fictional men's grooming and wardrobe e-commerce business.

> Built for the MGT5492 Data Management & Engineering module (MSc Business Analytics, University of Glasgow). The business and all data are synthetic.

## Table of Contents
- [At a Glance](#at-a-glance)
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

Nine business questions, each answered by one query in [`sql/02_analytical_queries.sql`](sql/02_analytical_queries.sql). Full outputs are saved as CSV in [`results/`](results/).

| # | Business question | Technique | Used by | Key finding |
|---|---|---|---|---|
| 1 | Who are the top 5 spenders in each loyalty tier? | CTE + `DENSE_RANK()` | Marketing | The top Silver customer (£237.99) out-spends the top Gold customer (£209.97), a signal that tier rules may need review. |
| 2 | How does monthly revenue split across products, combos and subscriptions? | Conditional aggregation | Management | November 2024 was the peak month: £4,660 from 52 orders, with products the largest channel every month. |
| 3 | Which products have high stock but no sales in the last 30 days? | `NOT EXISTS` subquery | Warehouse | 43 of 70 products have more than 20 units in stock and no sales in the final 30 days: candidates for promotion or lower reordering. |
| 4 | Which combo bundles earn more than £200? | `GROUP BY` + `HAVING` | Product | The Premium Grooming Box sold 44 times for £3,080, five times more than any other bundle. |
| 5 | Which delivery zones are late most often? | `DATEDIFF()` | Customer Service | All six zones show zero average delay and no failed deliveries: the synthetic sample has no late orders, so the query is ready for real data. |
| 6 | Which customers are at risk of churning? | CTE + recency banding | Marketing | 8 customers are High Risk (60+ days since last order) and 11 Medium Risk (40–59 days). |
| 7 | Which products have the highest margin? | Margin calculation | Finance | Low-price items lead on margin: Alum Block (55.5%), Beard Comb Set (55.0%), Sea Salt Spray (54.5%). |
| 8 | Which orders are 50% above the average order value? | Scalar subquery | Marketing | 17 orders exceed 1.5 × the £77.01 average order value: upsell targets. |
| 9 | How well do subscription cohorts retain? | Cohort grouping + `COALESCE` | Finance | The August and September 2024 cohorts keep 83% of subscribers; every other cohort has no active subscribers left. |

### Sample results (first 5 rows)

Click a question to see its output.

<details>
<summary><b>Q1.</b> Who are the top 5 spenders in each loyalty tier? (15 rows)</summary>

| CustomerName | TierLevel | TotalSpent | AverageOrderValue | TotalTransactions | RankInTier |
|---|---|---|---|---|---|
| William Perez | Bronze | 152.38 | 76.19 | 2 | 1 |
| Daniel Rogers | Bronze | 127.19 | 127.19 | 1 | 2 |
| Alexander Edwards | Bronze | 121.19 | 121.19 | 1 | 3 |
| Benjamin Campbell | Bronze | 116.39 | 116.39 | 1 | 4 |
| Jack Hall | Bronze | 111.59 | 111.59 | 1 | 5 |

Full output: [`results/q1_top_customers_by_tier.csv`](results/q1_top_customers_by_tier.csv)

</details>

<details>
<summary><b>Q2.</b> How does monthly revenue split across products, combos and subscriptions? (3 rows)</summary>

| SalesMonth | ProductRevenue | ComboRevenue | SubscriptionRevenue | TotalOrders |
|---|---|---|---|---|
| 2024-12 | 1684.84 | 999.94 | 1119.84 | 43 |
| 2024-11 | 1750.78 | 1579.89 | 1329.81 | 52 |
| 2024-10 | 1082.81 | 399.94 | 489.93 | 25 |

Full output: [`results/q2_monthly_revenue_by_channel.csv`](results/q2_monthly_revenue_by_channel.csv)

</details>

<details>
<summary><b>Q3.</b> Which products have high stock but no sales in the last 30 days? (43 rows)</summary>

| ProductName | SKU | QuantityOnHand | CategoryName |
|---|---|---|---|
| Beard Comb Set | GRM-BRDCMB-0005 | 610 | Beard Care |
| Alum Block | GRM-SHALUM-0020 | 550 | Shaving |
| Matte Clay Pomade | GRM-HRPMD1-0011 | 530 | Hair Care |
| Beard Trimming Scissors | GRM-BRDSCR-0003 | 520 | Beard Care |
| Leather Coin Purse | ACC-COIN1-0059 | 510 | Small Leather Goods |

Full output: [`results/q3_inventory_alert.csv`](results/q3_inventory_alert.csv)

</details>

<details>
<summary><b>Q4.</b> Which combo bundles earn more than £200? (8 rows)</summary>

| ComboName | TimesSold | TotalRevenue |
|---|---|---|
| Premium Grooming Box | 44 | 3079.56 |
| Leather Gentleman | 3 | 599.97 |
| Business Professional | 2 | 499.98 |
| Winter Warmers | 2 | 459.98 |
| Weekend Essentials | 3 | 419.97 |

Full output: [`results/q4_combo_performance.csv`](results/q4_combo_performance.csv)

</details>

<details>
<summary><b>Q5.</b> Which delivery zones are late most often? (6 rows)</summary>

| ZoneName | TotalDeliveries | AvgDelayDays | FailedCount |
|---|---|---|---|
| Central London | 41 | 0.0000 | 0 |
| Greater London | 2 | 0.0000 | 0 |
| Manchester Metropolitan | 17 | 0.0000 | 0 |
| Birmingham City Centre | 16 | 0.0000 | 0 |
| Glasgow City Centre | 3 | 0.0000 | 0 |

Full output: [`results/q5_delivery_performance.csv`](results/q5_delivery_performance.csv)

</details>

<details>
<summary><b>Q6.</b> Which customers are at risk of churning? (41 rows)</summary>

| CustomerName | TierLevel | LastOrderDate | DaysSinceLastOrder | TotalOrders | ChurnRiskLevel |
|---|---|---|---|---|---|
| James Anderson | Bronze | 2024-10-15 10:32:00 | 76 | 1 | High Risk |
| Mohammed Ali | Silver | 2024-10-16 14:24:00 | 75 | 1 | High Risk |
| Sarah Williams | Bronze | 2024-10-18 09:47:00 | 73 | 1 | High Risk |
| Evie Reed | Silver | 2024-10-19 10:17:00 | 72 | 1 | High Risk |
| Alfie Cook | Silver | 2024-10-21 14:52:00 | 70 | 1 | High Risk |

Full output: [`results/q6_churn_risk.csv`](results/q6_churn_risk.csv)

</details>

<details>
<summary><b>Q7.</b> Which products have the highest margin? (10 rows)</summary>

| ProductName | UnitPrice | CostPrice | ProfitPerUnit | MarginPercentage | CategoryName |
|---|---|---|---|---|---|
| Alum Block | 8.99 | 4.00 | 4.99 | 55.51 | Shaving |
| Beard Comb Set | 9.99 | 4.50 | 5.49 | 54.95 | Beard Care |
| Sea Salt Spray | 10.99 | 5.00 | 5.99 | 54.50 | Hair Care |
| Badger Hair Shaving Brush | 34.99 | 16.00 | 18.99 | 54.27 | Shaving |
| Charcoal Face Wash | 11.99 | 5.50 | 6.49 | 54.13 | Skincare |

Full output: [`results/q7_product_profitability.csv`](results/q7_product_profitability.csv)

</details>

<details>
<summary><b>Q8.</b> Which orders are 50% above the average order value? (17 rows)</summary>

| OrderID | Customer | TotalAmount | AverageOrderValue |
|---|---|---|---|
| 22 | Freya Mitchell | 152.39 | 77.01 |
| 38 | Jacob Cooper | 147.59 | 77.01 |
| 10 | Amelia Evans | 143.99 | 77.01 |
| 30 | Charlotte Morris | 142.79 | 77.01 |
| 118 | Isabella Parker | 140.00 | 77.01 |

Full output: [`results/q8_big_spenders.csv`](results/q8_big_spenders.csv)

</details>

<details>
<summary><b>Q9.</b> How well do subscription cohorts retain? (14 rows)</summary>

| CohortMonth | InitialSubscribers | StillActive | RetentionRate | AvgLifetimeDays |
|---|---|---|---|---|
| 2024-11 | 1 | 0 | 0.00 | 58.0000 |
| 2024-10 | 1 | 0 | 0.00 | 76.0000 |
| 2024-09 | 6 | 5 | 83.33 | 106.6667 |
| 2024-08 | 6 | 5 | 83.33 | 133.6667 |
| 2024-07 | 2 | 0 | 0.00 | 135.0000 |

Full output: [`results/q9_subscription_cohorts.csv`](results/q9_subscription_cohorts.csv)

</details>

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

```text
-- Without index
-> Aggregate using temporary table
    -> Nested loop inner join
        -> Table scan on o  (rows=120)
        -> Single-row covering index lookup on c using PRIMARY

-- With index
-> Group aggregate: sum(o.TotalAmount)
    -> Nested loop inner join
        -> Covering index scan on c using PRIMARY  (rows=60)
        -> Index lookup on o using idx_customer_date (CustomerID=c.CustomerID)
```

With only 120 sample orders, timings are too small to be meaningful. The value of the change is the execution plan: the query no longer scans the whole `Order` table or builds a temporary table, which matters as order volume grows.

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
├── .github/workflows/
│   └── test-sql.yml                      # runs all scripts on MySQL 8.0 on every push
├── sql/
│   ├── 01_schema_and_sample_data.sql     # database, 18 tables, constraints, sample data
│   ├── 02_analytical_queries.sql         # 9 business queries
│   ├── 03_indexing_and_performance.sql   # composite indexes + EXPLAIN ANALYZE
│   └── 04_security_rbac.sql              # users, grants, masked views
├── results/                              # full output of each query (CSV)
└── docs/
    └── data_dictionary.md                # column-level documentation
```

## Scope & Limitations

- This is an **operational (OLTP) database**, optimised for recording transactions correctly. Heavy reporting would normally run on a separate dimensional model (star schema) in a data warehouse.
- The business and all data are synthetic (about 50–120 rows per table), so performance results show changes in execution plans rather than realistic timings.
- Next step: a separate BI project building an ETL pipeline, a star-schema warehouse and Power BI dashboards on real retail data.

## Key Learnings

- **3NF vs denormalisation**: normalising to remove anomalies, then denormalising only where history or audit requires it
- **Security by design**: least-privilege access and masked views instead of trusting every user with raw tables
- **Performance tuning**: choosing indexes from real query patterns and checking the execution plan, not just timings

## Contact

**Danh Duc Luong (Lucas) Le** · MSc Business Analytics, University of Glasgow
luong.ldd.work@gmail.com · [LinkedIn](https://www.linkedin.com/in/lucasle68/)
