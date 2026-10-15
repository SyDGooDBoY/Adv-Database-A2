# Member 5 table reference (KYC/AML exceptions and reporting)

This document explains, in plain language, what each table and column in the
Member 5 module is for. It lists every table and every column, and is written to be
usable directly in the report.

---

## 1. What this module does, in one paragraph

The bank runs three systems — CRM, lending, and AML/KYC — and the same customer
carries a different reference in each of them. **Member 5 owns the compliance
check**: whether a customer's KYC evidence is complete and still valid, and whether
anti-money-laundering screening has produced a hit. When something is wrong it
**opens a case** to follow up, and finally reports which exceptions exist, how long
they have been open, and whether they have cleared.

The flow of data:

```
Bronze raw record  →  Silver event table        →  Silver case table        →  Gold exception fact
  raw_kyc_verification   kyc_verification_record    special_verification_case   fact_compliance_exception
  raw_aml_screening      aml_screening_result       aml_case
```

---

## 2. Table summary

| Layer | Table | One row is | Rows accumulate? |
|---|---|---|---|
| Silver | `kyc_verification_record` | One KYC verification a customer went through | Yes: an event log, so one customer has several rows |
| Silver | `special_verification_case` | One KYC problem that needs following up | No: one row per problem |
| Silver | `aml_screening_result` | One screening of a customer against a list | Yes: an event log |
| Silver | `aml_case` | One AML investigation | No: one row per alert |
| Gold | `fact_compliance_exception` | One reported exception | One row per source case, updated as it moves |

**The distinction between an event table and a case table is the core of the
design:**

- An **event table** is a log. One row per occurrence, never overwritten. Three
  verifications produce three rows.
- A **case table** records a problem. One row per problem, and a repeated finding
  **reuses** the open case rather than opening another, so the same fault never
  produces twenty cases.

---

## 3. Table by table, column by column

### 3.1 `silver.kyc_verification_record` — KYC verification events

> One row: what kind of verification a customer went through on a given day, and
> what the result was.

| Column | Meaning | Notes |
|---|---|---|
| `kyc_verification_id` | **Primary key.** Verification event identifier | Derived from source system and source reference, so a rerun produces the same key and no duplicate row |
| `customer_id` | The merged **golden customer** | Null means identity resolution has not finished; use the next column to locate the record |
| `source_customer_record_id` | The **source customer record** | Points at the source system's own customer record |
| `source_system_id` | Source system | Always `AMLKYC` for this module |
| `reviewed_by` | Who reviewed it | Optional. A record that is missing evidence should not name a reviewer |
| `source_kyc_reference` | The source system's own reference | For example `VFY-004`, used to reconcile against the source data |
| `verification_type` | Kind of check | Identity document, address, source of funds, enhanced due diligence, periodic review |
| `verification_status` | Outcome | VERIFIED, PENDING, **MISSING_DOCUMENT**, FAILED, EXPIRED |
| `verification_date` | When the verification happened | |
| `expiry_date` | Date the check stops being valid | **This is what decides whether the check can still be relied on**, compared against the reporting date |
| `risk_level_at_verification` | Risk level at the time | A historical snapshot, so it does not move when the customer's current level does |

**Which cases become exceptions?** Missing document, pending or failed becomes
`KYC_GAP`. Past the expiry date becomes `STATUS_DISCREPANCY`.

---

### 3.2 `silver.special_verification_case` — verification cases

> One row: a KYC problem that needs a person to follow it up.

| Column | Meaning | Notes |
|---|---|---|
| `verification_case_id` | **Primary key.** Case identifier | One per verification event and problem type, which is what makes reuse work |
| `customer_id` | Golden customer concerned | May be null while identity is unresolved |
| `source_customer_record_id` | Source customer record concerned | Identifies the subject even with no golden customer |
| `match_id` | The customer match behind the case | Used by cases about a doubtful match |
| `kyc_verification_id` | **The event that opened this case** | Points into `kyc_verification_record` |
| `assigned_user_id` | Who is handling it | May be null, meaning nobody is assigned yet |
| `case_type` | **Case type, one of three** | `KYC_GAP` missing evidence, `IDENTITY_MISMATCH` identity does not line up, `STATUS_DISCREPANCY` the record contradicts itself |
| `trigger_type` | What kind of subject triggered it | Golden customer or source customer record |
| `case_reason` | Why the case was opened | Written as "rule name: problem description", so the reason is visible at a glance |
| `case_status` | Case state | Open, in progress, resolved, closed |
| `severity` | Severity | LOW, MEDIUM, HIGH, CRITICAL |
| `opened_at` | When it was opened | Taken from **business time**, not script runtime, so a rerun cannot inflate the age |
| `resolved_at` | When it was closed | Only set once resolved or closed |
| `resolution_outcome` | What cleared it | The reason the finding was accepted as cleared |

---

### 3.3 `silver.aml_screening_result` — AML screening events

> One row: one screening of a customer against a list, and how close the match was.

| Column | Meaning | Notes |
|---|---|---|
| `aml_screening_id` | **Primary key.** Screening event identifier | Derived from the source reference, so reruns are idempotent |
| `customer_id` | Golden customer screened | May be null |
| `source_customer_record_id` | Source customer record screened | |
| `source_system_id` | Source system | `AMLKYC` |
| `source_screening_reference` | The source system's own reference | For example `SCR-005-2` |
| `screening_type` | List category | Sanctions, politically exposed person, watchlist, adverse media |
| `screening_date` | When the screening ran | |
| `screening_result` | Outcome | CLEAR, **POTENTIAL_MATCH**, CONFIRMED_MATCH, FALSE_POSITIVE |
| `match_score` | Similarity | 0 to 1, higher meaning closer to the listed person. **Evidence, not a conclusion** |
| `provider_reference` | The provider's own reference | Kept so the original result can be traced |
| `review_required_flag` | Whether a person must review it | Must be true for any alert, otherwise the source system under-reported |

> **The business point:** a list hit is only a suspicion. It therefore opens a
> **review** case; it does not label the customer.

---

### 3.4 `silver.aml_case` — AML investigation cases

> One row: one anti-money-laundering investigation. It can come from a screening
> alert or from another documented signal.

| Column | Meaning | Notes |
|---|---|---|
| `aml_case_id` | **Primary key.** Case identifier | One per screening event and case type |
| `customer_id` | Golden customer concerned | May be null |
| `source_customer_record_id` | Source customer record concerned | |
| `aml_screening_id` | **The screening event that triggered it** | May be null when the case came from another signal |
| `assigned_user_id` | Who is investigating | May be null |
| `trigger_type` | What kind of signal triggered it | Sanctions, PEP, watchlist, adverse media, other alert |
| `trigger_reference` | Text reference for the trigger | Written as "rule name: source customer reference" |
| `case_type` | Case type | This module uses `AML_SCREENING_REVIEW`, which keeps the emphasis on review rather than conclusion |
| `case_status` | Case state | Open, under investigation, closed |
| `risk_level` | Risk level | LOW, MEDIUM, HIGH, CRITICAL |
| `opened_at` | When it was opened | Taken from the triggering screening's business time |
| `closed_at` | When it was closed | Only set once closed |
| `case_outcome` | What the investigation concluded | The review result and why nothing further is needed |

---

### 3.5 `gold.fact_compliance_exception` — the exception fact behind the report

> One row: **one exception**. This is an **accumulating** fact table: while a case is
> open, each refresh **updates the same row** rather than adding one, which is what
> makes "how long has this been open" meaningful.

| Column | Meaning | Notes |
|---|---|---|
| `exception_fact_id` | **Primary key.** Exception identifier | Derived from source type and case identifier, so a refresh lands on the same row |
| `customer_key` | Warehouse customer key | Points at `dim_customer`. Null while identity is unresolved, filled in later |
| `verification_case_id` | Case reference for a KYC exception | **Must be null** when the source is AML |
| `aml_case_id` | Case reference for an AML exception | **Must be null** when the source is a verification case |
| `exception_source_type` | Where the exception came from | `VERIFICATION` for KYC, `AML` for anti-money-laundering |
| `exception_type` | Kind of exception | Carried from the case type: `KYC_GAP`, `STATUS_DISCREPANCY`, `AML_SCREENING_REVIEW` |
| `exception_status` | State of the exception | Open, in progress, resolved, closed |
| `severity` | Severity | LOW, MEDIUM, HIGH, CRITICAL |
| `opened_date` | Date the case opened | Where the age starts counting |
| `resolved_date` | Date it closed | Null while open |
| `as_of_date` | **The reporting date** | How far the data runs; an open case's age is counted to this date |
| `days_open` | **Age in days** | Closing date, or the reporting date while open, minus the opening date, and **never beyond the reporting date** |
| `last_updated_at` | When this row was last refreshed | Used to judge how fresh the data is |

> **Two rules to remember:** exactly one of the two case references is filled and it
> must agree with the source type; and each source case appears in the table only
> once.

---

## 4. Views this module creates

| View | Purpose |
|---|---|
| `gold.vw_kyc_aml_exception_report` | **The exception report.** One row per exception, with the reason it was opened, the event behind it and the closing conclusion. Exceptions with an unresolved identity are **kept**, not filtered out |
| `gold.vw_compliance_exception_summary` | Totals by customer, source and type: exception count, open count, closed count, longest age, highest severity |
| `silver.vw_kyc_aml_exception_lineage` | **Lineage.** Chains raw record to published event to case to reported exception, which is how a conclusion is explained to an auditor |

> The "highest severity" in the summary view is taken by an explicit order of
> CRITICAL, HIGH, MEDIUM, LOW. Alphabetical order would rank MEDIUM above HIGH,
> which would be wrong.

---

## 5. How this module meets the other members

This module describes **only the objects it owns** and does not change another
member's tables, so their descriptions are never overwritten. The points of contact:

| Table | Owner | How this module uses it |
|---|---|---|
| `bronze.raw_kyc_verification`, `bronze.raw_aml_screening` | Member 1 | **Read only.** Raw records are read from here and never modified |
| `bronze.raw_aml_kyc_customer` | Member 1 | **Read only.** Customer attributes are taken from here to build an identity |
| `silver.customer_master`, `silver.source_customer_record` | Member 2 | Existing identities are reused. One is created **only when the identity an event references does not exist yet**, and a resolved identity is never rewritten |
| `silver.data_quality_issue` | Shared, Member 6 | This module **writes** its own findings and fills in the case reference for KYC ones |
| `silver.data_lineage_record` | Shared | This module **writes** lineage for the events it publishes |
| `gold.dim_customer` | Member 4 | **Read only**, used to attach a customer key to an exception |

---

## 6. Reading the descriptions from the database

**CloudBeaver or DBeaver**: expand a table and read the Comment column in the
Columns panel; a table's own description is in its properties.

**With SQL**:

```sql
-- Every column of one table, with its description
SELECT
  c.ordinal_position AS position,
  c.column_name      AS column_name,
  c.data_type        AS data_type,
  col_description('silver.kyc_verification_record'::regclass, c.ordinal_position) AS description
FROM information_schema.columns c
WHERE c.table_schema = 'silver'
  AND c.table_name = 'kyc_verification_record'
ORDER BY c.ordinal_position;

-- The table descriptions for all five tables at once
SELECT
  c.relname              AS table_name,
  obj_description(c.oid) AS description
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE (n.nspname, c.relname) IN (
  ('silver', 'kyc_verification_record'),
  ('silver', 'special_verification_case'),
  ('silver', 'aml_screening_result'),
  ('silver', 'aml_case'),
  ('gold',   'fact_compliance_exception')
);
```

---

## 7. What this module contains

| Object | Count | Notes |
|---|---|---|
| Tables | 5 | Four Silver tables and one Gold fact table |
| Columns | 62 | **Every column** of those five tables, described in section 3 |
| Views | 3 | The report, the summary and the lineage view |
| Functions | 13 | Identifiers, identity resolution, rule detection, case lookup and opening |
| Procedures | 9 | Batch staging, event publication, case publication and progress, fact refresh |

Two notes:

1. These descriptions use PostgreSQL's `COMMENT ON ... IS` syntax, not MySQL's
   `COMMENT` keyword. Section 3 states the same content, so it can be read without
   running anything.
2. A description **replaces** rather than appends: PostgreSQL keeps one description
   per object, so setting one overwrites whatever was there.

Written by `09_add_object_descriptions.sql`, which is idempotent and may be rerun at
any time after `00`-`07`.
