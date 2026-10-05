-- PostgreSQL 15+
-- Physical layers defined by the report's Medallion Architecture.

CREATE SCHEMA IF NOT EXISTS source_systems;
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

