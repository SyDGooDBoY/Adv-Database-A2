# Shared database setup

These scripts implement the PostgreSQL structure described in the report. Run
them in filename order.

## Build order

1. `00_create_schemas.sql` creates the four physical layers.
2. `10_source_system_tables.sql` creates simulated operational tables aligned
   with the supplied CSV files.
3. `20_bronze_raw_tables.sql` creates the immutable raw landing tables.
4. `30`-`35` create the six Silver functional domains from the logical model.
5. `40_gold_reporting_analytics.sql` creates the Gold dimensional model.
6. `45_create_reporting_views.sql` reserves the two report-defined analytical
   views for later implementation.
7. `49_add_foreign_keys.sql` adds relationships after every referenced table
   exists.
8. `50`-`70` are the ordered data-load entry points for later development.

## Model coverage

The 24 logical entities from `Untitled.sql` are distributed across the six
Silver domain files and the Gold file. All 16 unique indexes, 24 table comments
and 50 foreign keys from that source are retained. Physical names use normal
PostgreSQL lowercase identifiers; the report's uppercase names remain the
logical entity names.

`base_people.csv` and `expected_identity_map.csv` are validation fixtures, not
operational source entities, so no production tables are created for them.

The report mentions `vw_single_customer` and
`vw_customer_account_history`, but `Untitled.sql` does not define them. Their
placeholder file therefore contains no invented view logic.

