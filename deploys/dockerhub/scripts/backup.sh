#!/bin/bash
# PostgreSQL 11 Backup Script

set -e

# Configuration
BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_DB=${POSTGRES_DB:-postgres}

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [BACKUP] $1"
}

# Create backup
create_backup() {
    local backup_file="$BACKUP_DIR/postgres_${POSTGRES_DB}_${TIMESTAMP}.sql"
    
    log "Creating backup of database: $POSTGRES_DB"
    log "Backup file: $backup_file"
    
    if pg_dump -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$backup_file"; then
        log "✅ Backup created successfully: $backup_file"
        
        # Compress the backup
        if gzip "$backup_file"; then
            log "✅ Backup compressed: ${backup_file}.gz"
        fi
        
        # List recent backups
        log "📋 Recent backups:"
        ls -lah "$BACKUP_DIR"/*.gz 2>/dev/null | tail -5 || log "No compressed backups found"
    else
        log "❌ Backup failed"
        exit 1
    fi
}

# Clean old backups (keep last 7 days)
cleanup_old_backups() {
    log "Cleaning up backups older than 7 days..."
    find "$BACKUP_DIR" -name "postgres_*.sql.gz" -mtime +7 -delete 2>/dev/null || true
    log "✅ Cleanup completed"
}

# Main execution
main() {
    log "Starting PostgreSQL backup process..."
    create_backup
    cleanup_old_backups
    log "🎉 Backup process completed successfully!"
}

# Execute if called directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
