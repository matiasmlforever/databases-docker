#!/bin/bash
# filepath: e:\DEV\databases-docker\deploys\dockerhub\scripts\init-db.sh

set -e

echo "🔧 Starting custom PostgreSQL initialization..."
echo "================================================="

# Function to log with timestamp
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
}

# Note: No need to wait for PostgreSQL to be ready in init scripts
# The Docker entrypoint ensures PostgreSQL is running when init scripts execute

log_info "PostgreSQL initialization script starting..."
log_info "Environment variables:"
log_info "  POSTGRES_USER: ${POSTGRES_USER}"
log_info "  POSTGRES_DB: ${POSTGRES_DB}"
log_info "  POSTGRES_PASSWORD: [PROTECTED]"
log_info "  APP_USER: ${APP_USER}"
log_info "  APP_DATABASE: ${APP_DATABASE}"
log_info "  APP_PASSWORD: [PROTECTED]"

# Check if this is a fresh installation
if [ ! -f "/var/lib/postgresql/data/custom_init_completed" ]; then
    log_info "Fresh installation detected, running custom initialization..."
    
    # Set password encryption method globally
    log_info "🔐 Setting password encryption to SCRAM-SHA-256..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
        -- Set password encryption for new passwords
        ALTER SYSTEM SET password_encryption = 'scram-sha-256';
        
        -- Reload configuration to apply changes immediately
        SELECT pg_reload_conf();
        
        -- Show current setting
        SHOW password_encryption;
EOSQL

    # Create application database and user
    log_info "📊 Creating application database and user..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
        -- Create the application user if it doesn't exist with SCRAM password
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_USER}') THEN
                -- Force SCRAM-SHA-256 encryption for this password
                SET password_encryption = 'scram-sha-256';
                CREATE ROLE "${APP_USER}" WITH LOGIN PASSWORD '${APP_PASSWORD}';
                RAISE NOTICE 'Created user: ${APP_USER} with SCRAM-SHA-256 password';
            ELSE
                RAISE NOTICE 'User ${APP_USER} already exists';
            END IF;
        END
        \$\$;
        
        -- Create the application database if it doesn't exist
        SELECT 'CREATE DATABASE "${APP_DATABASE}" OWNER "${APP_USER}"' 
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${APP_DATABASE}')\gexec
        
        -- Grant necessary privileges to the application user
        GRANT CREATE, CONNECT ON DATABASE "${APP_DATABASE}" TO "${APP_USER}";
        
        -- Also ensure the postgres database exists and has proper permissions
        SELECT 'CREATE DATABASE "${POSTGRES_DB}"' 
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_DB}')\gexec
        
        -- Grant privileges on the postgres database to superuser
        GRANT ALL PRIVILEGES ON DATABASE "${POSTGRES_DB}" TO "${POSTGRES_USER}";
EOSQL

    # Verify both users can connect to their respective databases
    log_info "🧪 Testing connections..."
    
    # Test superuser connection to postgres database
    log_info "Testing postgres superuser connection..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        -- Simple connectivity test for superuser
        SELECT 'Superuser connection successful! User: ' || current_user || ', Database: ' || current_database() AS status;
        
        -- Show superuser info
        SELECT rolname AS usename, rolsuper AS usesuper, rolcreatedb AS usecreatedb, rolcanlogin 
        FROM pg_roles 
        WHERE rolname = current_user;
EOSQL
    
    # Test app user exists and has correct privileges (skip actual connection during init)
    log_info "Verifying application user configuration..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
        -- Verify app user exists with correct settings
        SELECT 
            'App user verification: ' || rolname || ' exists with login=' || rolcanlogin || ', superuser=' || rolsuper AS status
        FROM pg_roles 
        WHERE rolname = '${APP_USER}';
        
        -- Verify app database exists and ownership
        SELECT 
            'App database verification: ' || datname || ' owned by ' || pg_catalog.pg_get_userbyid(datdba) AS status
        FROM pg_database 
        WHERE datname = '${APP_DATABASE}';
        
        -- Note: TCP connection test will be performed after server restart with proper config
        SELECT 'Note: Application user TCP connection will be tested after container startup' AS info;
EOSQL

    # Mark initialization as completed
    touch "/var/lib/postgresql/data/custom_init_completed"
    log_info "✅ Custom initialization completed successfully!"
    
else
    log_info "Custom initialization already completed, skipping..."
fi

echo "================================================="
echo "🎉 PostgreSQL initialization finished!"
echo "   Superuser: ${POSTGRES_USER} -> Database: ${POSTGRES_DB}"
echo "   App User: ${APP_USER} -> Database: ${APP_DATABASE}"
echo "   Authentication: SCRAM-SHA-256"
echo "   Status: Ready for connections!"
echo "   "
echo "   Connection examples:"
echo "   psql -h localhost -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
echo "   psql -h localhost -U ${APP_USER} -d ${APP_DATABASE}"
echo "================================================="