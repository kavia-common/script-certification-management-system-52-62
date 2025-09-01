-- Migration: 000_bootstrap.sql
-- Purpose: Ensure the migrations tracking table exists.

BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
    id BIGSERIAL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum VARCHAR(64) NULL
);

COMMIT;
