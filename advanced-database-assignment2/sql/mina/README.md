# Member 2 - Final Version

## What each file does

### 01
Moves successful Bronze customer versions into `silver.source_customer_record`.

### 02
Standardises name, DOB, email, phone and address for matching, while preserving the original source values.

### 03
Applies simple deterministic rules:
- strong agreement -> `ACCEPTED`
- DOB conflict + same name/phone -> `PENDING_REVIEW`
- otherwise -> `NO_MATCH`

### 04
Assigns one enterprise `customer_id` to accepted records using normal SQL grouping.
There is no Neo4j, no graph database, and no recursive graph logic.

It only creates placeholder rows in `customer_master`.
Member 3 still owns survivorship and authoritative customer attributes.

### 05
Runs simple validation queries for:
- retained versions
- current records
- enterprise customer count
- Alice
- Daniel
- Ethan
- Ava

## Short explanation

> My module works in the Silver layer. I first retain the successful Bronze customer versions, then standardise fields such as name, email, phone and address before matching. I compare records across CRM, Lending and AML/KYC using deterministic rules. Strong matches are accepted, while conflicting information such as Daniel's DOB difference is sent for manual review. Accepted source records are grouped under one enterprise customer ID. I only create a placeholder customer master row because final attribute survivorship belongs to Module 3.