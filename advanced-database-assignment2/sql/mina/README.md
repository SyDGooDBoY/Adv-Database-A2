# Member 2 - Customer Identity Matching

This folder is tailored to the current repository and to Member 1's completed
ingestion / CDC module.

## Exact hand-off from Member 1

Member 1's README states that Member 1 stops after producing:

- reliable append-only Bronze data; and
- validated Silver ingestion / CDC control records.

Customer standardisation and identity matching are explicitly downstream work.

Therefore Member 2 starts from the three Bronze customer tables:

- `bronze.raw_crm_customer`
- `bronze.raw_lending_customer`
- `bronze.raw_aml_kyc_customer`

and publishes / uses these Silver entities:

- `silver.source_customer_record`
- `silver.customer_source_match`
- `silver.customer_master` (identity shell only)

Member 3 remains responsible for attribute survivorship and history:

- `silver.customer_attribute_source`
- `silver.customer_history`
- authoritative attributes in `silver.customer_master`

## Do I change `00_shared_setup`?

No change is required for Member 2.

The shared setup already creates all required tables in
`31_silver_customer_identity_resolution.sql`.

The placeholder `70_seed_initial_silver.sql` describes the same Bronze-to-Silver
handoff, but this implementation is kept in the Member 2 folder so the team's
shared setup remains unchanged. The team can later decide whether to turn
`70_seed_initial_silver.sql` into a shared orchestration entry point.

## Run order in a clean database

1. Shared setup: run `sql/00_shared_setup/00...49` in filename order.
2. Member 1: run `sql/hongfei/01...06` in filename order.
3. Member 2:
   1. `01_standardise_source_customer_records.sql`
   2. `02_prepare_matching_candidates.sql`
   3. `03_apply_matching_rules.sql`
   4. `04_assign_unified_customers.sql`
   5. `05_validation_tests.sql`

Member 1's `07_validation_tests.sql` may also be run to verify Member 1 before
starting Member 2.

## What each Member 2 file does

### 01_standardise_source_customer_records.sql

Publishes successful Bronze customer versions into
`silver.source_customer_record`.

It:
- ignores Bronze batches that failed validation;
- retains inserts, updates and delete versions;
- closes the previous source version when a later version appears;
- marks delete versions as non-current;
- supports reruns without duplicate source versions.

### 02_prepare_matching_candidates.sql

Creates normalised matching fields without changing retained source values.

It standardises:
- names;
- email case;
- phone formatting;
- address formatting.

It then generates candidate pairs only across different source systems.

### 03_apply_matching_rules.sql

Classifies candidate pairs as:
- `ACCEPTED`;
- `PENDING_REVIEW`; or
- `NO_MATCH`.

The supplied Daniel DOB-conflict scenario is deliberately routed to review.

### 04_assign_unified_customers.sql

Treats accepted pair decisions as graph edges and assigns one enterprise
customer ID to every connected set of source identities.

It also:
- creates accepted decisions for single-source customers;
- writes `silver.customer_source_match`;
- flags uncertain source records for manual review;
- closes old matches when Member 1 supplies a newer version or deletion;
- reuses existing customer IDs where possible across reruns.

`silver.customer_master` receives only an identity shell with
`PENDING_SURVIVORSHIP`. Member 2 does not choose final name, DOB, email, phone
or address values.

### 05_validation_tests.sql

Checks the supplied scenarios after Member 1's B2 demo, including:
- Alice: three source records -> one customer;
- Daniel: Lending record -> manual review because DOB conflicts;
- Maya: address difference does not prevent identity resolution;
- Ethan: CRM email update keeps the same identity;
- Ava: CRM delete leaves no current source identity;
- Grace: three source records -> one customer;
- Mia: late CRM insert becomes a new current customer.

`expected_identity_map.csv` is only a test oracle. It is not read by the
matching algorithm.

## CloudBeaver workflow

Open each file in VS Code, copy it into a CloudBeaver SQL editor and execute the
whole file. Run the five files in order.

If Step 1 returns no records, verify that Member 1 has been run and that the
relevant rows in `silver.ingestion_batch` are `SUCCEEDED`.
