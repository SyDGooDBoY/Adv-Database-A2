# Module 3 — Attribute Conflict Resolution and History

## Purpose
Use current ACCEPTED matches from Module 2 to select customer
attributes, update the customer master, and retain provenance,
history and lineage.

## Files
- 01_prepare_survivorship_candidates.sql — prepare eligible values.
- 02_apply_survivorship.sql — create the processing procedure.
- 03_validation_tests.sql — validate outputs and rerun behaviour.

## Prototype Rules
- Name, date of birth and address: prefer nonblank AMLKYC values,
  then CRM, then LEND.
- Email and phone: prefer the latest nonblank value.
- Exclude pending-review matches.
- Retain historical records when sources are deleted.

These source preferences are prototype assumptions for team review,
not verified bank policies.

## Timestamp Semantics
When Module 3 updates `customer_master`, `last_updated_at`
records the processing time, not the source business update time.

Candidate ranking uses `source_last_updated_at`.
Module 3 provenance and history periods use processing time.

## Run Order
Complete shared setup and Modules 1 and 2 first.
Run files 01 and 02, then:

CALL silver.apply_member3_survivorship();

Finally, run file 03.

To demonstrate update history, run Module 3 after B1 and again after B2.

## Testing
Local PGlite integration tests passed.
Verification on the shared PostgreSQL server is still required.
