-- PostgreSQL 15+
-- Add all relationships only after Source, Bronze, Silver and Gold tables exist.
-- Keeping cross-domain foreign keys here makes each domain file independently
-- maintainable and prevents execution-order failures.

ALTER TABLE silver.ingestion_batch ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.cdc_change_event ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.data_quality_issue ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.data_quality_issue ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.data_quality_issue ADD FOREIGN KEY (verification_case_id) REFERENCES silver.special_verification_case (verification_case_id);

ALTER TABLE silver.data_lineage_record ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.data_lineage_record ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.source_customer_record ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.customer_source_match ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.customer_source_match ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.customer_source_match ADD FOREIGN KEY (reviewed_by_user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.customer_attribute_source ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.customer_history ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.banking_account ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.banking_account ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.account_transaction ADD FOREIGN KEY (account_id) REFERENCES silver.banking_account (account_id);

ALTER TABLE silver.account_transaction ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.loan ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.loan ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.kyc_verification_record ADD FOREIGN KEY (reviewed_by) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (match_id) REFERENCES silver.customer_source_match (match_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (kyc_verification_id) REFERENCES silver.kyc_verification_record (kyc_verification_id);

ALTER TABLE silver.special_verification_case ADD FOREIGN KEY (assigned_user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.aml_screening_result ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.aml_screening_result ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.aml_screening_result ADD FOREIGN KEY (source_system_id) REFERENCES silver.source_system (source_system_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (source_customer_record_id) REFERENCES silver.source_customer_record (source_customer_record_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (aml_screening_id) REFERENCES silver.aml_screening_result (aml_screening_id);

ALTER TABLE silver.aml_case ADD FOREIGN KEY (assigned_user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.customer_risk_assessment ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE silver.user_account ADD FOREIGN KEY (role_id) REFERENCES silver.role (role_id);

ALTER TABLE silver.access_audit_log ADD FOREIGN KEY (user_id) REFERENCES silver.user_account (user_id);

ALTER TABLE silver.access_audit_log ADD FOREIGN KEY (role_id) REFERENCES silver.role (role_id);

ALTER TABLE gold.dim_customer ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE gold.fact_customer_snapshot ADD FOREIGN KEY (customer_id) REFERENCES silver.customer_master (customer_id);

ALTER TABLE gold.fact_customer_snapshot ADD FOREIGN KEY (risk_assessment_id) REFERENCES silver.customer_risk_assessment (risk_assessment_id);

ALTER TABLE gold.fact_compliance_exception ADD FOREIGN KEY (customer_key) REFERENCES gold.dim_customer (customer_key);

ALTER TABLE gold.fact_compliance_exception ADD FOREIGN KEY (verification_case_id) REFERENCES silver.special_verification_case (verification_case_id);

ALTER TABLE gold.fact_compliance_exception ADD FOREIGN KEY (aml_case_id) REFERENCES silver.aml_case (aml_case_id);

ALTER TABLE silver.cdc_change_event ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.source_customer_record ADD FOREIGN KEY (batch_id) REFERENCES silver.ingestion_batch (batch_id);

ALTER TABLE silver.customer_attribute_source ADD FOREIGN KEY (match_id) REFERENCES silver.customer_source_match (match_id);

ALTER TABLE silver.customer_history ADD FOREIGN KEY (attribute_source_id) REFERENCES silver.customer_attribute_source (attribute_source_id);

ALTER TABLE gold.fact_customer_snapshot ADD FOREIGN KEY (customer_key) REFERENCES gold.dim_customer (customer_key);
