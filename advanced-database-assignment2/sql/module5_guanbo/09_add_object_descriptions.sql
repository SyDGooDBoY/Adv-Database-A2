-- PostgreSQL 15+
-- Member 5: catalogue descriptions for every object this module owns.
--
-- Run after 00-07. Idempotent: PostgreSQL keeps one description per object, so
-- rerunning replaces rather than appends. Only this module's own objects are
-- described, so no other member's descriptions are overwritten.

-- ---------------------------------------------------------------- tables
COMMENT ON TABLE silver.kyc_verification_record IS
  'One KYC verification attempt. An event table: it records what the source system reported and is never rewritten by the review that follows. Where a record has to be superseded, a new version is inserted (source_kyc_reference plus version).';

COMMENT ON TABLE silver.special_verification_case IS
  'One case opened to follow up a reportable KYC finding. A case table: it records the decision taken about an event, so it changes over time. At most one case exists per KYC event and case type, so a repeated finding reuses the open case.';

COMMENT ON TABLE silver.aml_screening_result IS
  'One AML screening of a customer against watchlists and sanctions lists. An event table, and the counterpart of silver.kyc_verification_record. A screening result is a signal, not a conclusion: a hit is a suspected match.';

COMMENT ON TABLE silver.aml_case IS
  'One investigation opened from an AML screening alert. A case table, the counterpart of silver.special_verification_case. At most one case exists per screening event and case type.';

COMMENT ON TABLE gold.fact_compliance_exception IS
  'Accumulating snapshot fact for the KYC/AML exception report: one row per originating case, updated in place as the case moves. Dates are the reporting view of the case, so days_open can be capped at the reporting date without touching the case itself.';

-- ------------------------------------------- silver.kyc_verification_record
COMMENT ON COLUMN silver.kyc_verification_record.kyc_verification_id IS
  'Primary key, derived from the source system and the source KYC reference so that reprocessing the same record produces the same key.';
COMMENT ON COLUMN silver.kyc_verification_record.customer_id IS
  'Golden customer, once identity resolution has merged this customer. Null while the identity is unresolved, and the report keeps the row either way.';
COMMENT ON COLUMN silver.kyc_verification_record.source_customer_record_id IS
  'The Silver record for the source system''s own customer. Present even when no golden customer has been resolved.';
COMMENT ON COLUMN silver.kyc_verification_record.source_system_id IS
  'Source system this event came from, which with source_kyc_reference identifies the record.';
COMMENT ON COLUMN silver.kyc_verification_record.reviewed_by IS
  'The user who performed the verification, when the source system records one.';
COMMENT ON COLUMN silver.kyc_verification_record.source_kyc_reference IS
  'The source system''s own reference for this verification. Part of the derived primary key.';
COMMENT ON COLUMN silver.kyc_verification_record.verification_type IS
  'The kind of check performed. An unrecognised value is reported by the KYC_VERIFICATION_TYPE_INVALID rule.';
COMMENT ON COLUMN silver.kyc_verification_record.verification_status IS
  'Reported outcome. Read together with expiry_date: a status of VERIFIED whose expiry has passed is reported as a status discrepancy.';
COMMENT ON COLUMN silver.kyc_verification_record.verification_date IS
  'When the verification was performed. Used with the reporting date to decide whether the record had expired by then.';
COMMENT ON COLUMN silver.kyc_verification_record.expiry_date IS
  'Date the verification stops being valid. Null means no expiry was recorded, which KYC_VERIFICATION_EXPIRY_MISSING reports.';
COMMENT ON COLUMN silver.kyc_verification_record.risk_level_at_verification IS
  'Customer risk level as it stood at verification time, kept because the current level may have moved since.';

-- ------------------------------------------ silver.special_verification_case
COMMENT ON COLUMN silver.special_verification_case.verification_case_id IS
  'Primary key, derived from the KYC event and the case type, so a repeated finding lands on the same case.';
COMMENT ON COLUMN silver.special_verification_case.customer_id IS
  'Golden customer the case concerns. Null while the identity is unresolved.';
COMMENT ON COLUMN silver.special_verification_case.source_customer_record_id IS
  'The source customer record behind the event, kept so the case can be traced even with no golden customer.';
COMMENT ON COLUMN silver.special_verification_case.match_id IS
  'The identity match that linked the source record to the golden customer, when one was used.';
COMMENT ON COLUMN silver.special_verification_case.kyc_verification_id IS
  'The KYC verification event that triggered the case.';
COMMENT ON COLUMN silver.special_verification_case.assigned_user_id IS
  'The user handling the case, when one has been assigned.';
COMMENT ON COLUMN silver.special_verification_case.case_type IS
  'Why the case exists: KYC_GAP, IDENTITY_MISMATCH or STATUS_DISCREPANCY, as the report requires.';
COMMENT ON COLUMN silver.special_verification_case.trigger_type IS
  'What opened the case, so a case can be traced back to the rule that produced it.';
COMMENT ON COLUMN silver.special_verification_case.case_reason IS
  'Human-readable reason, carried from the finding that opened the case.';
COMMENT ON COLUMN silver.special_verification_case.case_status IS
  'Open, under review, resolved and so on. A case closes only once its finding has cleared.';
COMMENT ON COLUMN silver.special_verification_case.severity IS
  'Case severity on the case scale. BLOCKING never appears here: that belongs to a data quality issue.';
COMMENT ON COLUMN silver.special_verification_case.opened_at IS
  'When the case was opened, taken from the triggering event''s business time so a rerun cannot inflate the case age.';
COMMENT ON COLUMN silver.special_verification_case.resolved_at IS
  'When the case was closed. Null while it is open, and kept in step with case_status by the progress step.';
COMMENT ON COLUMN silver.special_verification_case.resolution_outcome IS
  'What the review concluded, recorded when the case closes.';

-- ------------------------------------------------- silver.aml_screening_result
COMMENT ON COLUMN silver.aml_screening_result.aml_screening_id IS
  'Primary key, derived from the source system and the source screening reference so reprocessing is idempotent.';
COMMENT ON COLUMN silver.aml_screening_result.customer_id IS
  'Golden customer, once identity resolution has merged this customer. Null while unresolved.';
COMMENT ON COLUMN silver.aml_screening_result.source_customer_record_id IS
  'The Silver record for the source system''s own customer, present even with no golden customer.';
COMMENT ON COLUMN silver.aml_screening_result.source_system_id IS
  'Source system this screening came from.';
COMMENT ON COLUMN silver.aml_screening_result.source_screening_reference IS
  'The source system''s own reference for this screening. Part of the derived primary key.';
COMMENT ON COLUMN silver.aml_screening_result.screening_type IS
  'The list or check applied, such as sanctions or PEP. An unrecognised value is reported by AML_SCREENING_TYPE_INVALID.';
COMMENT ON COLUMN silver.aml_screening_result.screening_date IS
  'When the screening ran.';
COMMENT ON COLUMN silver.aml_screening_result.screening_result IS
  'The outcome, such as CLEAR, POTENTIAL_MATCH or CONFIRMED_MATCH. An alert without review_required_flag is reported as contradictory.';
COMMENT ON COLUMN silver.aml_screening_result.match_score IS
  'Similarity, from 0.0000 to 1.0000. A score outside that range, or an alert with no score at all, is reported.';
COMMENT ON COLUMN silver.aml_screening_result.provider_reference IS
  'The screening provider''s own reference, kept for reconciliation with the vendor.';
COMMENT ON COLUMN silver.aml_screening_result.review_required_flag IS
  'Whether a person has to review the result. Required for any alert, and not allowed for a low-scoring near miss.';

-- ---------------------------------------------------------------- silver.aml_case
COMMENT ON COLUMN silver.aml_case.aml_case_id IS
  'Primary key, derived from the screening event and the case type, so a repeated alert reuses the same case.';
COMMENT ON COLUMN silver.aml_case.customer_id IS
  'Golden customer under investigation. Null while the identity is unresolved.';
COMMENT ON COLUMN silver.aml_case.source_customer_record_id IS
  'The source customer record behind the alert.';
COMMENT ON COLUMN silver.aml_case.aml_screening_id IS
  'The screening event that raised the alert this case investigates.';
COMMENT ON COLUMN silver.aml_case.assigned_user_id IS
  'The investigator handling the case, when one has been assigned.';
COMMENT ON COLUMN silver.aml_case.trigger_type IS
  'What opened the case, so it can be traced back to the alert that produced it.';
COMMENT ON COLUMN silver.aml_case.trigger_reference IS
  'The reference of the triggering alert.';
COMMENT ON COLUMN silver.aml_case.case_type IS
  'Why the case exists, for example AML_SCREENING_REVIEW. A rule with no mapping on this table opens no case.';
COMMENT ON COLUMN silver.aml_case.case_status IS
  'Open, under investigation, closed and so on. A case closes only once its alert no longer stands.';
COMMENT ON COLUMN silver.aml_case.risk_level IS
  'Investigation risk level. Topped at HIGH, so a blocking finding maps to HIGH rather than CRITICAL.';
COMMENT ON COLUMN silver.aml_case.opened_at IS
  'When the case was opened, taken from the alert''s business time.';
COMMENT ON COLUMN silver.aml_case.closed_at IS
  'When the case was closed. Null while it is open, and kept in step with case_status.';
COMMENT ON COLUMN silver.aml_case.case_outcome IS
  'What the investigation concluded, recorded when the case closes.';

-- -------------------------------------------- gold.fact_compliance_exception
COMMENT ON COLUMN gold.fact_compliance_exception.exception_fact_id IS
  'Primary key, derived from the source type and the case identifier, so refreshing a case updates its row.';
COMMENT ON COLUMN gold.fact_compliance_exception.customer_key IS
  'Dimension key for the golden customer. Null while the identity is unresolved, which is why the report joins with a left join.';
COMMENT ON COLUMN gold.fact_compliance_exception.verification_case_id IS
  'The verification case this row reports. Filled for KYC exceptions and null for AML ones.';
COMMENT ON COLUMN gold.fact_compliance_exception.aml_case_id IS
  'The AML case this row reports. Filled for AML exceptions and null for KYC ones.';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_source_type IS
  'Which case table the row came from: VERIFICATION or AML. Exactly one of the two case columns is filled to match.';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_type IS
  'The kind of exception, such as KYC_GAP or AML_SCREENING_REVIEW, carried from the case type.';
COMMENT ON COLUMN gold.fact_compliance_exception.exception_status IS
  'The fact''s own view of the case state, mapped from the case status. Kept here because the fact reports state over time.';
COMMENT ON COLUMN gold.fact_compliance_exception.severity IS
  'Severity on the case scale, so the report and the case agree.';
COMMENT ON COLUMN gold.fact_compliance_exception.opened_date IS
  'Date the case was opened, which is where days_open starts counting.';
COMMENT ON COLUMN gold.fact_compliance_exception.resolved_date IS
  'Date the case was closed, or null while it is open. This is the real closing date, not the capped one.';
COMMENT ON COLUMN gold.fact_compliance_exception.as_of_date IS
  'The reporting date this row was last refreshed for. Refreshing an open case for a later date updates the same row.';
COMMENT ON COLUMN gold.fact_compliance_exception.days_open IS
  'Calendar days from opening to closing, or to as_of_date while open, capped at as_of_date so a report cannot claim an age longer than its own period.';
COMMENT ON COLUMN gold.fact_compliance_exception.last_updated_at IS
  'When the row was last refreshed, so a report can tell a fresh row from a stale one.';

-- ---------------------------------------------------------------- views
COMMENT ON VIEW gold.vw_kyc_aml_exception_report IS
  'The KYC/AML exception report: one row per reported exception with its originating case detail and the customer name. Cases whose identity is still unresolved are kept through a left join rather than dropped.';

COMMENT ON VIEW gold.vw_compliance_exception_summary IS
  'Exception totals by customer and exception type, for the summary block of the report.';

COMMENT ON VIEW silver.vw_kyc_aml_exception_lineage IS
  'Traceability for the report: each published exception followed back from the exception fact, through the case, to the Silver event and the retained Bronze record.';

-- ---------------------------------------------------------------- functions
COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  'Stable key for a KYC verification event, derived from the source system and source KYC reference so reprocessing adds no duplicate row.';

COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  'Stable key for an AML screening event, derived from the source system and source screening reference, as for the KYC version.';

COMMENT ON FUNCTION gold.compliance_exception_fact_id(varchar, varchar) IS
  'Stable key for an exception fact row, derived from the source type and the case identifier so a refresh updates the same row.';

COMMENT ON FUNCTION silver.resolve_event_identity(varchar, varchar, varchar, varchar) IS
  'Resolve the source customer record and golden customer for one event. Both are null when nothing is found, which is how a caller detects an identity that is not merged yet.';

COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  'Apply the eight KYC verification rules to one batch, returning only the most severe finding per record. A null batch checks every batch at its latest Bronze version.';

COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  'Apply the ten AML screening rules to one batch, returning only the most severe finding per record. A null batch checks every batch at its latest Bronze version.';

COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  'The single rule-to-case-type mapping the report requires. A null result means the rule stays a quality record and opens no case.';

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Register one finding as a Silver data quality issue and return the case type for its rule. The issue key is derived from batch, rule and record, so a rerun updates that one row.';

COMMENT ON FUNCTION silver.find_or_open_case(varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Shared find-or-open step: one case per subject and case type, reused when it already exists. Used by both the KYC and the AML case functions.';

COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open the verification case for a KYC finding and return its identifier, which is written back to the data quality issue.';

COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open the AML investigation case for a screening alert. Nothing is written back, because the issue table links only a verification case.';

COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  'Dispatch a finding to the right case function. Returns a verification case id for KYC findings and null for AML ones.';

COMMENT ON FUNCTION silver.customer_kyc_status(date) IS
  'Customer KYC status under the reporting rule: VERIFIED only when every required verification succeeded and is unexpired with no unresolved relevant exception, otherwise INCOMPLETE, REVIEW_REQUIRED or UNKNOWN. One row per golden customer, evaluated at the given date.';

-- --------------------------------------------------------------- procedures
COMMENT ON PROCEDURE silver.stage_bronze_batch(varchar, varchar) IS
  'Stage one batch''s Bronze rows and attach the identity lookup result, so the rules and the publisher share one evaluation.';

COMMENT ON PROCEDURE silver.record_event_lineage(varchar, varchar) IS
  'Record published events in the lineage table, linking each Bronze record to the Silver event it produced. Republishing adds nothing, because the lineage key is derived.';

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  'Validate one batch of Bronze KYC verification rows and publish them to Silver, withholding any row that carries a blocking finding.';

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  'Validate one batch of Bronze AML screening rows and publish them to Silver, withholding any row that carries a blocking finding.';

COMMENT ON PROCEDURE silver.load_kyc_aml_customer_identity() IS
  'Create the minimum customer identity this module''s events reference. Existing resolutions are left untouched; only missing ones are added.';

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Batch entry point: resolve customer identity, publish the KYC and AML events to Silver, then run the rules and register the findings.';

COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  'Open or reuse a case for every open finding and write the verification case id back to the issue. Safe to rerun.';

COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  'Reconcile case status against current evidence: resolve findings the rules no longer report, close the cases they clear, and leave a case with an open finding open so its age keeps accruing.';

COMMENT ON PROCEDURE gold.refresh_compliance_exception_fact(date) IS
  'Refresh the exception fact for one reporting date, from both case tables. Updating an open case updates its existing row; a stale row whose case is gone is removed.';
