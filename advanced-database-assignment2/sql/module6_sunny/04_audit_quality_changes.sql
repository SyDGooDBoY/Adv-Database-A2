-- Member 6: demonstrate automatic auditing of issue INSERT/UPDATE/DELETE.
-- Run after shared tables exist. The trigger records successful, committed
-- row changes; it does not record SELECT, failed statements or rollbacks.

CREATE OR REPLACE FUNCTION silver.member6_audit_quality_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, silver
AS $member6_audit$
DECLARE
  v_record_reference text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_record_reference := OLD.data_quality_issue_id;
  ELSE
    v_record_reference := NEW.data_quality_issue_id;
  END IF;

  INSERT INTO silver.access_audit_log (
    audit_id, user_id, role_id, actor_identifier, query_reference,
    action_type, resource_name, record_reference,
    event_timestamp, success_flag, ip_address
  )
  VALUES (
    'M6A-' || substr(md5(
      clock_timestamp()::text || random()::text || v_record_reference
    ), 1, 32),
    NULL, NULL, session_user::text,
    NULLIF(current_setting('application_name', true), ''),
    TG_OP, TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
    v_record_reference, clock_timestamp(), TRUE,
    inet_client_addr()::text
  );

  RETURN NULL; -- return value ignored by an AFTER trigger
END;
$member6_audit$;

REVOKE ALL ON FUNCTION silver.member6_audit_quality_write() FROM PUBLIC;

DO $member6_attach_audit$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'silver.data_quality_issue'::regclass
      AND tgname = 'tr_member6_quality_issue_audit'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER tr_member6_quality_issue_audit
    AFTER INSERT OR UPDATE OR DELETE ON silver.data_quality_issue
    FOR EACH ROW EXECUTE FUNCTION silver.member6_audit_quality_write();
  END IF;
END;
$member6_attach_audit$;

CREATE OR REPLACE FUNCTION silver.member6_prevent_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $member6_append_only$
BEGIN
  RAISE EXCEPTION 'silver.access_audit_log is append-only';
END;
$member6_append_only$;

REVOKE ALL ON FUNCTION silver.member6_prevent_audit_mutation() FROM PUBLIC;

DO $member6_attach_protection$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'silver.access_audit_log'::regclass
      AND tgname = 'tr_member6_audit_append_only'
      AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER tr_member6_audit_append_only
    BEFORE UPDATE OR DELETE ON silver.access_audit_log
    FOR EACH ROW EXECUTE FUNCTION silver.member6_prevent_audit_mutation();
  END IF;
END;
$member6_attach_protection$;

COMMENT ON FUNCTION silver.member6_audit_quality_write() IS
  'Audit committed quality-issue row changes using the database login as actor. Does not provide SELECT auditing.';
