# Member 2 - Commented Version

This version keeps the same integration boundary and table/view interfaces used by the team, but adds comments intended for demonstration.

## Run order

After shared setup and Module 1:

1. `01_standardise_source_customer_records.sql`
2. `02_prepare_matching_candidates.sql`
3. `03_apply_matching_rules.sql`
4. `04_assign_unified_customers.sql`
5. `05_validation_tests.sql`


## Compatibility

The scripts continue to use the existing shared objects:

- `silver.source_customer_record`
- `silver.customer_master`
- `silver.customer_source_match`
- `silver.ingestion_batch`

and the existing Module 2 view names:

- `silver.v_member2_bronze_customer_versions`
- `silver.v_member2_matching_input`
- `silver.v_member2_match_candidates`
- `silver.v_member2_pair_decisions`

The explicit `NULL::date` / `NULL::varchar(...)` casts are included in Step 4 to avoid the PostgreSQL type-resolution issue reported during integration testing.