-- PostgreSQL 15+
-- Silver - Security and User Access
-- Split from Untitled.sql according to the report's functional domains.
-- Foreign keys are added later by 49_add_foreign_keys.sql.

CREATE TABLE silver.role (
  role_id varchar(50) PRIMARY KEY NOT NULL,
  role_name varchar(100) NOT NULL,
  role_description varchar(500)
);

CREATE TABLE silver.user_account (
  user_id varchar(50) PRIMARY KEY NOT NULL,
  role_id varchar(50) NOT NULL,
  username varchar(100) NOT NULL,
  full_name varchar(150) NOT NULL,
  email_address varchar(150),
  department varchar(100),
  account_status varchar(30) NOT NULL,
  created_at timestamp NOT NULL,
  last_login_at timestamp
);

CREATE TABLE silver.access_audit_log (
  audit_id varchar(50) PRIMARY KEY NOT NULL,
  user_id varchar(50),
  role_id varchar(50),
  actor_identifier varchar(150) NOT NULL,
  query_reference varchar(150),
  action_type varchar(50) NOT NULL,
  resource_name varchar(200) NOT NULL,
  record_reference varchar(150),
  event_timestamp timestamp NOT NULL,
  success_flag boolean NOT NULL,
  ip_address varchar(50)
);

CREATE UNIQUE INDEX role_index_10 ON silver.role (role_name);

CREATE UNIQUE INDEX user_account_index_11 ON silver.user_account (username);

COMMENT ON TABLE silver.role IS 'One prototype access role. role_name is unique.';

COMMENT ON TABLE silver.user_account IS 'One internal user with one primary role in the prototype. username is unique. Internal users are distinct from bank customers.';

COMMENT ON TABLE silver.access_audit_log IS 'One auditable access, query or action event. Append-only. Preserve actor and role at the event time. user_id may be null for an unidentified actor; query_reference is optional for non-query actions.';
