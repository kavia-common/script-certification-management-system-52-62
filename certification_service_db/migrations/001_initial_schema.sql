-- Migration: 001_initial_schema.sql
-- Purpose: Establish foundational schema for certification_service_db

BEGIN;

-- Table: certification_jobs
CREATE TABLE IF NOT EXISTS certification_jobs (
    id BIGSERIAL PRIMARY KEY,
    repository_url TEXT NOT NULL,
    commit_sha VARCHAR(64) NOT NULL,
    branch_name VARCHAR(255) NOT NULL,
    environment VARCHAR(255) NOT NULL,
    certification_types TEXT[] NOT NULL, -- array of certification type identifiers
    status VARCHAR(50) NOT NULL DEFAULT 'queued', -- queued, running, succeeded, failed, canceled
    triggered_by VARCHAR(255) NOT NULL, -- api, webhook, schedule, user:<id>, etc.
    priority INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ NULL,
    completed_at TIMESTAMPTZ NULL,
    metadata JSONB NULL, -- job-level metadata, overrides, parameters
    UNIQUE (commit_sha, certification_types, environment) -- avoid duplicates per commit/types/env
);

-- Minimal helpful indexes for certification_jobs
CREATE INDEX IF NOT EXISTS idx_cert_jobs_status ON certification_jobs (status);
CREATE INDEX IF NOT EXISTS idx_cert_jobs_branch ON certification_jobs (branch_name);
CREATE INDEX IF NOT EXISTS idx_cert_jobs_commit ON certification_jobs (commit_sha);
CREATE INDEX IF NOT EXISTS idx_cert_jobs_created_at ON certification_jobs (created_at DESC);

-- Table: certification_results
CREATE TABLE IF NOT EXISTS certification_results (
    id BIGSERIAL PRIMARY KEY,
    job_id BIGINT NOT NULL REFERENCES certification_jobs(id) ON DELETE CASCADE,
    certification_type VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL, -- passed, failed, skipped, error
    score NUMERIC(10,4) NULL, -- optional numeric score
    summary TEXT NULL,
    details JSONB NULL, -- structured results, measurements, logs references
    logs_url TEXT NULL, -- external logs location (e.g., S3, ELK)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (job_id, certification_type)
);

-- Minimal helpful indexes for certification_results
CREATE INDEX IF NOT EXISTS idx_cert_results_job ON certification_results (job_id);
CREATE INDEX IF NOT EXISTS idx_cert_results_type ON certification_results (certification_type);
CREATE INDEX IF NOT EXISTS idx_cert_results_status ON certification_results (status);

-- Table: branch_environment_mappings
CREATE TABLE IF NOT EXISTS branch_environment_mappings (
    id BIGSERIAL PRIMARY KEY,
    repository_url TEXT NOT NULL,
    branch_pattern VARCHAR(255) NOT NULL, -- supports glob-like patterns (e.g., release/*)
    environment VARCHAR(255) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB NULL,
    UNIQUE (repository_url, branch_pattern)
);

-- Minimal helpful indexes for branch_environment_mappings
CREATE INDEX IF NOT EXISTS idx_bem_repo ON branch_environment_mappings (repository_url);
CREATE INDEX IF NOT EXISTS idx_bem_env ON branch_environment_mappings (environment);

-- Table: certification_metadata
CREATE TABLE IF NOT EXISTS certification_metadata (
    id BIGSERIAL PRIMARY KEY,
    key VARCHAR(255) NOT NULL,
    value JSONB NOT NULL,
    description TEXT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (key)
);

-- Minimal helpful indexes for certification_metadata
CREATE INDEX IF NOT EXISTS idx_cmeta_active ON certification_metadata (is_active);

-- Table: audit_logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL, -- e.g., api_call, override, mapping_change
    actor VARCHAR(255) NOT NULL, -- user id, service name or api key id
    action VARCHAR(255) NOT NULL, -- e.g., trigger_certification, override_types
    target_type VARCHAR(100) NULL, -- job, mapping, metadata, system
    target_id VARCHAR(255) NULL, -- id of target entity as text
    request_id VARCHAR(255) NULL, -- correlation id
    payload JSONB NULL, -- request/changes payload
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Minimal helpful indexes for audit_logs
CREATE INDEX IF NOT EXISTS idx_audit_event_type ON audit_logs (event_type);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_logs (actor);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs (created_at DESC);

-- Triggers to auto-update updated_at fields
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_jobs_updated_at ON certification_jobs;
CREATE TRIGGER trg_jobs_updated_at
BEFORE UPDATE ON certification_jobs
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_results_updated_at ON certification_results;
CREATE TRIGGER trg_results_updated_at
BEFORE UPDATE ON certification_results
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_bem_updated_at ON branch_environment_mappings;
CREATE TRIGGER trg_bem_updated_at
BEFORE UPDATE ON branch_environment_mappings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_cmeta_updated_at ON certification_metadata;
CREATE TRIGGER trg_cmeta_updated_at
BEFORE UPDATE ON certification_metadata
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
