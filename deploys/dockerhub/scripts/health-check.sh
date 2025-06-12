#!/bin/bash
# PostgreSQL 11 Health Check Script for Docker

set -e

# Health check function
health_check() {
    # Use environment variable or default to postgres
    local check_user="${POSTGRES_USER:-postgres}"
    local check_db="${POSTGRES_DB:-postgres}"
    
    # Check if PostgreSQL is accepting connections
    if pg_isready -h localhost -p 5432 -U "$check_user" -q; then
        # Try to connect and run a simple query with password
        if PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -p 5432 -U "$check_user" -d "$check_db" -c "SELECT 1;" > /dev/null 2>&1; then
            echo "✅ PostgreSQL is healthy"
            exit 0
        else
            echo "❌ PostgreSQL is not accepting queries"
            exit 1
        fi
    else
        echo "❌ PostgreSQL is not ready"
        exit 1
    fi
}

# Run health check
health_check
