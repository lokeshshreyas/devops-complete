-- Thermos Bookmark Manager - PostgreSQL Initialization
-- This script runs automatically when PostgreSQL container starts for the first time
-- The database 'thermos' is already created via POSTGRES_DB environment variable

-- The Flask app uses SQLAlchemy to create tables automatically
-- This file can be extended with initial seed data or custom schemas if needed

-- Example: Create a schema (optional)
-- CREATE SCHEMA IF NOT EXISTS app;

-- Example: Create extensions (optional)
-- CREATE EXTENSION IF NOT EXISTS uuid-ossp;
