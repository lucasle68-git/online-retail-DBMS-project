# Data Dictionary

Complete documentation of all 18 tables in The Gentleman's Hub database.

## Table of Contents
- [Core Transaction Flow](#core-transaction-flow)
  - [Order](#order)
  - [OrderItem](#orderitem)
  - [Customer](#customer)
  - [Address](#address)
  - [Product](#product)
  - [ProductCategory](#productcategory)
  - [ComboProduct](#comboproduct)
  - [ComboProductItem](#comboproductitem)
  - [Payment](#payment)
  - [Delivery](#delivery)
  - [DeliveryZone](#deliveryzone)
  - [ConsentRecord](#consentrecord)
- [Supporting Systems](#supporting-systems)
  - [LoyaltyAccount](#loyaltyaccount)
  - [LoyaltyTransaction](#loyaltytransaction)
  - [Subscription](#subscription)
  - [Inventory](#inventory)
  - [ReturnRequest](#returnrequest)
  - [Coupon](#coupon)

---

## Core Transaction Flow

### Order
**Purpose**: Central fact table in star schema - hub for all transactions

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| OrderID | INT | PK, AUTO_INCREMENT | Unique order identifier |
| CustomerID | INT | FK, NOT NULL | Reference to Customer |
| BillingID | INT | FK, NOT NULL | Reference to Payment |
| CouponID | INT | FK, NULL | Optional discount coupon |
| OrderDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Order creation timestamp |
| OrderType | ENUM | NOT NULL | 'StandardPurchase', 'SubscriptionBox', 'LoyaltyRedemption', 'GiftPurchase' |
| OrderStatus | ENUM | DEFAULT 'Pending' | 'Pending', 'Paid', 'Shipped', 'Cancelled', 'Delivered' |
| TaxAmount | DECIMAL(10,2) | DEFAULT 0.00 | VAT amount (immutable for audit) |
| ShippingFee | DECIMAL(10,2) | DEFAULT 0.00 | Delivery charge (immutable) |
| PaymentStatus | ENUM | DEFAULT 'Authorized' | 'Authorized', 'Captured', 'Failed' |
| TotalAmount | DECIMAL(10,2) | NOT NULL, CHECK >= 0 | Final order total |

**Indexes**: `idx_customer_date`, `idx_status`, `idx_type`, `idx_order_date`

---

### OrderItem
**Purpose**: Junction table linking orders to products/combos

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| OrderItemID | INT | PK, AUTO_INCREMENT | Unique line item identifier |
| OrderID | INT | FK, NOT NULL | Reference to Order |
| ComboID | INT | FK, NULL | Reference to ComboProduct (XOR with ProductID) |
| ProductID | INT | FK, NULL | Reference to Product (XOR with ComboID) |
| Quantity | INT | NOT NULL, CHECK > 0 | Items ordered |
| UnitPrice | DECIMAL(10,2) | NOT NULL | **Historical price at purchase** (denormalized) |

**Business Rule**: CHECK constraint ensures either ProductID OR ComboID is set, never both.

---

### Customer
**Purpose**: Master customer profiles

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| CustomerID | INT | PK, AUTO_INCREMENT | Unique customer identifier |
| FirstName | VARCHAR(100) | NOT NULL | Customer first name |
| LastName | VARCHAR(100) | NOT NULL | Customer surname |
| Email | VARCHAR(255) | UNIQUE, NOT NULL | Login/contact email |
| PhoneNumber | VARCHAR(20) | NULL | Contact number |
| DOB | DATE | NULL | Date of birth |
| CreatedDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Account creation |
| LastUpdated | DATETIME | ON UPDATE CURRENT_TIMESTAMP | Last profile update |

---

### Address
**Purpose**: Normalized customer addresses (1NF compliance)

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| AddressID | INT | PK, AUTO_INCREMENT | Unique address identifier |
| CustomerID | INT | FK, NOT NULL | Reference to Customer |
| AddressLine | VARCHAR(200) | NOT NULL | Street address |
| City | VARCHAR(100) | NOT NULL | City name |
| Postcode | VARCHAR(10) | NOT NULL | UK postcode |
| Country | VARCHAR(50) | DEFAULT 'United Kingdom' | Country |
| IsDefault | BOOLEAN | DEFAULT 0 | Default shipping address flag |
| CreatedDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Address added date |

**Cascade Rule**: ON DELETE CASCADE (address deleted when customer deleted - GDPR compliance)

---

### Product
**Purpose**: Product catalog dimension

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| ProductID | INT | PK, AUTO_INCREMENT | Unique product identifier |
| CategoryID | INT | FK, NOT NULL | Reference to ProductCategory |
| ProductName | VARCHAR(100) | NOT NULL | Display name |
| ProductDescription | VARCHAR(200) | NULL | Product details |
| UnitPrice | DECIMAL(10,2) | NOT NULL, CHECK > 0 | Retail price |
| CostPrice | DECIMAL(10,2) | CHECK >= 0 | **Sensitive**: Cost of goods (restricted access) |
| SKU | VARCHAR(50) | UNIQUE, NOT NULL | Stock keeping unit |
| IsActive | BOOLEAN | DEFAULT 1 | Product availability flag |
| CreatedDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Product added date |

**Referential Integrity**: ON DELETE RESTRICT (cannot delete category with products)

---

### ProductCategory
**Purpose**: Hierarchical product categorization

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| CategoryID | INT | PK, AUTO_INCREMENT | Unique category identifier |
| ParentCategoryID | INT | FK, NULL | Self-reference for hierarchy |
| CategoryName | VARCHAR(100) | NOT NULL | Category display name |
| Description | VARCHAR(200) | NULL | Category description |
| IsActive | BOOLEAN | DEFAULT 1 | Category active flag |

---

### ComboProduct
**Purpose**: Bundled product offerings

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| ComboID | INT | PK, AUTO_INCREMENT | Unique combo identifier |
| ComboName | VARCHAR(100) | NOT NULL | Bundle name |
| ComboDescription | VARCHAR(200) | NULL | Bundle details |
| StandardPrice | DECIMAL(10,2) | NOT NULL | Sum of individual prices |
| ComboPrice | DECIMAL(10,2) | NOT NULL | Discounted bundle price |
| IsActive | BOOLEAN | DEFAULT 1 | Combo availability |
| CreatedDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Combo created date |

**CHECK Constraints**: `ComboPrice < StandardPrice` AND `ComboPrice > 0`

---

### ComboProductItem
**Purpose**: Junction table for combo contents

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| ComboItemID | INT | PK, AUTO_INCREMENT | Unique item identifier |
| ComboID | INT | FK, NOT NULL | Reference to ComboProduct |
| ProductID | INT | FK, NOT NULL | Reference to Product |
| Quantity | INT | NOT NULL, CHECK > 0 | Products in combo |
| IsSubstitutable | BOOLEAN | DEFAULT 0 | Can substitute product |

**Unique Constraint**: (ComboID, ProductID) - prevents duplicate products in combo

---

### Payment
**Purpose**: PCI-DSS compliant payment processing

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| BillingID | INT | PK, AUTO_INCREMENT | Unique payment identifier |
| PaymentDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Transaction timestamp |
| PaymentType | VARCHAR(20) | NOT NULL | 'Purchase', 'Subscription', 'Refund' |
| PaymentMethodType | ENUM | NOT NULL | 'Visa', 'Mastercard', 'Amex', 'PayPal', 'ApplePay' |
| CardToken | VARCHAR(255) | NULL | **Sensitive**: Tokenized card reference |
| CardLastFour | VARCHAR(4) | NULL | Last 4 digits for display |
| CardBrand | VARCHAR(50) | NULL | Card issuer name |
| CardExpiryMonth | INT | CHECK 1-12 | Expiry month |
| CardExpiryYear | INT | CHECK >= 2025 | Expiry year |
| TransactionReference | VARCHAR(100) | NULL | Payment gateway reference |
| PaymentStatus | ENUM | DEFAULT 'Pending' | 'Pending', 'Authorized', 'Captured', 'Failed', 'Refunded' |

**⚠️ Security Note**: CVV/CVC is NEVER stored (PCI-DSS requirement)

---

### Delivery
**Purpose**: Shipment tracking

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| DeliveryID | INT | PK, AUTO_INCREMENT | Unique delivery identifier |
| OrderID | INT | FK, UNIQUE, NOT NULL | One delivery per order |
| ZoneID | INT | FK, NOT NULL | Reference to DeliveryZone |
| ScheduledDeliveryDate | DATE | NOT NULL | Promised delivery date |
| ScheduledTimeSlot | VARCHAR(50) | NULL | Delivery window |
| ActualDeliveryDate | DATETIME | NULL | Actual delivery timestamp |
| DeliveryStatus | ENUM | DEFAULT 'Processing' | 'Processing', 'InTransit', 'Delivered', 'Failed' |
| TrackingNumber | VARCHAR(100) | UNIQUE | Carrier tracking reference |

---

### DeliveryZone
**Purpose**: UK delivery zone capacity management

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| ZoneID | INT | PK, AUTO_INCREMENT | Unique zone identifier |
| ZoneName | VARCHAR(100) | NOT NULL | Zone display name |
| StandardDeliveryDays | INT | NOT NULL, DEFAULT 3 | Normal delivery SLA |
| MaxDailyCapacity | INT | NOT NULL | Maximum daily deliveries |
| PostcodePrefixes | VARCHAR(255) | NOT NULL | Comma-separated postcodes |
| IsActive | BOOLEAN | DEFAULT 1 | Zone operational status |

---

### ConsentRecord
**Purpose**: GDPR compliance - consent tracking per channel

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| ConsentID | INT | PK, AUTO_INCREMENT | Unique consent record |
| CustomerID | INT | FK, NOT NULL | Reference to Customer |
| ConsentType | ENUM | NOT NULL | 'Marketing', 'Cookies', 'Terms' |
| ConsentGiven | BOOLEAN | NOT NULL, DEFAULT 0 | Consent status |
| ConsentDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Consent timestamp |

**1NF Compliance**: Each consent type stored as separate row (not comma-separated)

---

## Supporting Systems

### LoyaltyAccount
**Purpose**: Customer loyalty program profiles

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| LoyaltyAccountID | INT | PK, AUTO_INCREMENT | Unique account identifier |
| CustomerID | INT | FK, NOT NULL | Reference to Customer |
| CurrentPointsBalance | INT | DEFAULT 0 | Available points |
| TotalPointsEarned | INT | DEFAULT 0 | Lifetime points |
| TierLevel | VARCHAR(20) | DEFAULT 'Bronze' | 'Bronze', 'Silver', 'Gold' |
| IsActive | BOOLEAN | DEFAULT 1 | Account active status |

---

### LoyaltyTransaction
**Purpose**: Points earn/redeem history

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| TransactionID | INT | PK, AUTO_INCREMENT | Unique transaction identifier |
| LoyaltyAccountID | INT | FK, NOT NULL | Reference to LoyaltyAccount |
| OrderID | INT | FK, NULL | Associated order (if applicable) |
| TotalPointsEarned | INT | NOT NULL | Points in transaction |
| TierLevel | ENUM | NOT NULL | 'Bronze', 'Silver', 'Gold' |
| IsActive | BOOLEAN | DEFAULT 1 | Transaction active |
| TransactionDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Transaction timestamp |

---

### Subscription
**Purpose**: Monthly subscription box management

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| SubscriptionID | INT | PK, AUTO_INCREMENT | Unique subscription identifier |
| CustomerID | INT | FK, NOT NULL | Reference to Customer |
| BoxType | ENUM | NOT NULL | 'BasicGrooming', 'PremiumGrooming', 'Wardrobe', 'Complete' |
| SubscriptionStatus | ENUM | DEFAULT 'Active' | 'Active', 'Paused', 'Cancelled' |
| BillingCycle | ENUM | DEFAULT 'Monthly' | 'Monthly', 'Quarterly', 'Annual' |
| MonthlyPrice | DECIMAL(10,2) | NOT NULL | Subscription cost |
| StartDate | DATE | NOT NULL | Subscription start |
| NextBillingDate | DATE | NULL | Next charge date |
| CancellationDate | DATE | NULL | Cancellation date (if applicable) |

---

### Inventory
**Purpose**: Real-time stock management

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| InventoryID | INT | PK, AUTO_INCREMENT | Unique inventory record |
| ProductID | INT | FK, NOT NULL | Reference to Product |
| QuantityOnHand | INT | NOT NULL, DEFAULT 0 | Current stock level |
| ReorderLevel | INT | DEFAULT 10 | Minimum stock threshold |
| ReorderQuantity | INT | DEFAULT 50 | Standard reorder amount |
| LastStockUpdate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Last inventory update |

---

### ReturnRequest
**Purpose**: Customer returns and refunds

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| ReturnID | INT | PK, AUTO_INCREMENT | Unique return identifier |
| OrderID | INT | FK, NOT NULL | Original order |
| CustomerID | INT | FK, NOT NULL | Customer requesting return |
| ReturnReason | VARCHAR(200) | NULL | Reason for return |
| ReturnStatus | ENUM | DEFAULT 'Requested' | 'Requested', 'Approved', 'Rejected', 'Completed' |
| RefundAmount | DECIMAL(10,2) | NULL | Amount to refund |
| RequestDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Return request date |
| ProcessedDate | DATETIME | NULL | Resolution date |

---

### Coupon
**Purpose**: Promotional discount codes

| Column | Data Type | Constraints | Description |
|--------|-----------|-------------|-------------|
| CouponID | INT | PK, AUTO_INCREMENT | Unique coupon identifier |
| Code | VARCHAR(20) | UNIQUE, NOT NULL | Coupon code (e.g., 'WELCOME10') |
| Description | VARCHAR(200) | NULL | Promotion details |
| DiscountType | ENUM | NOT NULL | 'Percent', 'FixedAmount' |
| DiscountValue | DECIMAL(10,2) | NOT NULL | Discount amount/percentage |
| MinOrderValue | DECIMAL(10,2) | DEFAULT 0.00 | Minimum order requirement |
| UsageLimit | INT | NULL | Maximum redemptions |
| UsageCount | INT | DEFAULT 0 | Current redemptions |
| IsActive | BOOLEAN | DEFAULT 1 | Coupon active status |
| CreatedDate | DATETIME | DEFAULT CURRENT_TIMESTAMP | Coupon created date |

---

## Referential Integrity Rules

| Parent | Child | ON DELETE | Rationale |
|--------|-------|-----------|-----------|
| Customer | Address | CASCADE | Remove addresses when customer deleted (GDPR) |
| Customer | Order | CASCADE | Remove orders when customer deleted |
| Customer | ConsentRecord | CASCADE | Remove consent when customer deleted |
| Customer | LoyaltyAccount | CASCADE | Remove loyalty when customer deleted |
| Order | OrderItem | CASCADE | Remove line items when order deleted |
| Order | Delivery | CASCADE | Remove delivery when order deleted |
| ProductCategory | Product | RESTRICT | Prevent category deletion if products exist |
| Product | ComboProductItem | RESTRICT | Prevent product deletion if in combos |
| ComboProduct | ComboProductItem | CASCADE | Remove items when combo deleted |
| Coupon | Order | SET NULL | Preserve orders when coupon expires |
