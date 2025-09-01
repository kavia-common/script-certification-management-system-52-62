#!/bin/bash

# Minimal PostgreSQL startup script with full paths
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Helper to run psql as postgres into target DB
psql_root_db() {
  sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d "$1"
}

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
    
    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi
    
    echo ""
else
    # Also check if there's a PostgreSQL process running (in case pg_isready fails)
    if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
        echo "Found existing PostgreSQL process on port ${DB_PORT}"
        echo "Attempting to verify connection..."
        
        # Try to connect and verify the database exists
        if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
            echo "Database ${DB_NAME} is accessible."
        fi
    fi

    # Initialize PostgreSQL data directory if it doesn't exist
    if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
        echo "Initializing PostgreSQL..."
        sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
    fi

    # Start PostgreSQL server in background
    echo "Starting PostgreSQL server..."
    sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &

    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 5

    # Check if PostgreSQL is running
    for i in {1..15}; do
        if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
            echo "PostgreSQL is ready!"
            break
        fi
        echo "Waiting... ($i/15)"
        sleep 2
    done
fi

# Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d postgres << EOF
-- Create user if doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the specific database for schema-level permissions
\c ${DB_NAME}

-- For PostgreSQL 15+, we need to handle public schema permissions differently
-- First, grant usage on public schema
GRANT USAGE ON SCHEMA public TO ${DB_USER};

-- Grant CREATE permission on public schema
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Make the user owner of all future objects they create in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

-- Alternative: Grant all privileges on schema public to the user
GRANT ALL ON SCHEMA public TO ${DB_USER};

-- Ensure the user can work with any existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Additionally, connect to the specific database to ensure permissions
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} << EOF
-- Double-check permissions are set correctly in the target database
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Show current permissions for debugging
\dn+ public
EOF

# Apply SQL migrations
echo "Applying database migrations..."
MIGRATIONS_DIR="$(pwd)/migrations"

apply_migration() {
  local file="$1"
  local checksum
  checksum=$(sha256sum "$file" | awk '{print $1}')
  local filename
  filename=$(basename "$file")

  # Ensure schema_migrations table exists (bootstrap)
  psql_root_db "${DB_NAME}" -v ON_ERROR_STOP=1 <<'EOSQL'
BEGIN;
CREATE TABLE IF NOT EXISTS schema_migrations (
  id BIGSERIAL PRIMARY KEY,
  filename VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checksum VARCHAR(64) NULL
);
COMMIT;
EOSQL

  # Check if already applied
  local exists
  exists=$(psql_root_db "${DB_NAME}" -At -c "SELECT 1 FROM schema_migrations WHERE filename='${filename}' LIMIT 1;" 2>/dev/null)
  if [ "${exists}" == "1" ]; then
    echo " - Skipping ${filename} (already applied)"
    return 0
  fi

  echo " - Running ${filename}"
  if psql_root_db "${DB_NAME}" -v ON_ERROR_STOP=1 -f "${file}"; then
    psql_root_db "${DB_NAME}" -v ON_ERROR_STOP=1 -c "INSERT INTO schema_migrations (filename, checksum) VALUES ('${filename}', '${checksum}');" >/dev/null
    echo "   Applied ${filename}"
  else
    echo "   Failed to apply ${filename}"
    exit 1
  fi
}

if [ -d "${MIGRATIONS_DIR}" ]; then
  # Apply in lexicographical order
  for migration in $(ls "${MIGRATIONS_DIR}"/*.sql 2>/dev/null | sort); do
    apply_migration "${migration}"
  done
else
  echo "No migrations directory found at ${MIGRATIONS_DIR}"
fi

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""

echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"

echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
