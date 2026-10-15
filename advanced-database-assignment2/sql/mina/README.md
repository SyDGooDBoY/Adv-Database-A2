# Module 2: Customer Identity Matching

## Purpose

Module 2 identifies which customer records from CRM, Lending and AML/KYC belong to the same real world customer.

It standardises identity fields, compares records across systems, applies deterministic matching rules, and assigns accepted records a shared enterprise `customer_id`.

Module 2 does not choose the final trusted name, email, phone or address. That is handled by Module 3 through attribute survivorship.

---

## Architecture

Module 2 operates in the Silver layer of the Medallion architecture.

```text
Module 1
Bronze ingestion / CDC 
Module 2
Customer identity matching
Unified customer_id
Module 3
Attribute survivorship
Golden customer record
```

The module uses the relational model with SQL tables, views, joins and grouping.

---

## Files

### `01_standardise_source_customer_records.sql`

Combines successful customer records from CRM, Lending and AML/KYC into `silver.source_customer_record`.

Main tasks:
- uses only successful ingestion batches
- preserves source record versions
- identifies the current version
- retains deleted and historical records
- generates a technical source-record ID

### `02_prepare_matching_candidates.sql`

Standardises the fields used for identity matching, including names, emails, phone numbers and addresses.

The original source values are not changed.

The script then uses a self-join to compare records from different source systems and creates indicators such as:

```text
name_match
dob_match
dob_conflict
email_match
phone_match
address_match
```

### `03_apply_matching_rules.sql`

Applies deterministic rules to each candidate pair.

Possible results:

```text
ACCEPTED
PENDING_REVIEW
NO_MATCH
```

Example rules:

```text
DOB + Email + Phone match
→ ACCEPTED

DOB + Name + Address match
→ ACCEPTED

DOB conflict + Name + Phone match
→ PENDING_REVIEW
```

A confidence score and matching rule are stored so the decision can be explained.

The confidence scores are prototype rule weights, not statistical probabilities.

### `04_assign_unified_customers.sql`

Assigns accepted source records to one enterprise `customer_id`.

Example:

```text
CRM-001
LEND-001
KYC-001
    ↓
CUST-XXXXXXXXXXXX
```

The script also:
- closes old identity mappings when source versions change;
- keeps unresolved records as `PENDING_REVIEW`;
- creates a placeholder row in `customer_master`;
- stores the final source-to-customer relationship in `customer_source_match`.

The placeholder `customer_master` row is not the final golden record. Module 3 later selects the trusted customer attributes.

### `05_validation_tests.sql`

Checks that the module produces the expected results.

Main test cases:
- **Alice:** three source records should share one customer ID.
- **Daniel:** DOB conflict should result in `PENDING_REVIEW`.
- **Ethan:** CRM version 2 should be the current matched record.
- **Ava:** deleted CRM record should no longer have a current match.

---

## Main Outputs

```text
silver.source_customer_record
silver.v_member2_matching_input
silver.v_member2_match_candidates
silver.v_member2_pair_decisions
silver.customer_source_match
silver.customer_master
```

The main final output of Module 2 is `silver.customer_source_match`, which links each source customer record to the unified enterprise customer.

---

## Run Order

Run the shared setup and Module 1 first.

Then run:

```text
01_standardise_source_customer_records.sql
02_prepare_matching_candidates.sql
03_apply_matching_rules.sql
04_assign_unified_customers.sql
05_validation_tests.sql
```

---

## Module 2 vs Module 3

```text
Module 2:
Which records belong to the same customer?

Module 3:
Which values become the trusted customer attributes?
```

Module 2 performs identity resolution.

Module 3 performs survivorship and creates the golden customer record.

---

## Prototype Notes

The matching rules and confidence scores are assumptions created for this prototype and synthetic dataset.

The simplified grouping approach is suitable for the current three-source prototype. A production system with more complex transitive matches would require a more advanced identity-resolution approach.