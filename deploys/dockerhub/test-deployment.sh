#!/bin/bash
# PostgreSQL 11 Deployment Test Script
# Tests an existing deployment to ensure it's working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

print_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Load environment variables
load_env() {
    if [ -f ".env.prod" ]; then
        print_info "Loading production environment variables from .env.prod"
        set -a
        source .env.prod
        set +a
    else
        print_error ".env.prod file not found"
        exit 1
    fi
}

# Test container existence and status
test_container_status() {
    local container_name="postgres11_prod"
    
    print_info "Testing container status..."
    
    if ! docker ps | grep -q "$container_name"; then
        if docker ps -a | grep -q "$container_name"; then
            print_error "Container $container_name exists but is not running"
            print_info "Container status:"
            docker ps -a | grep "$container_name"
            return 1
        else
            print_error "Container $container_name does not exist"
            return 1
        fi
    fi
    
    print_status "✅ Container is running"
    return 0
}

# Test PostgreSQL readiness
test_postgres_ready() {
    local container_name="postgres11_prod"
    
    print_info "Testing PostgreSQL readiness..."
    
    if docker exec "$container_name" pg_isready -h localhost -p 5432 -U "$POSTGRES_USER" -q; then
        print_status "✅ PostgreSQL is ready"
        return 0
    else
        print_error "❌ PostgreSQL is not ready"
        return 1
    fi
}

# Test database connection
test_database_connection() {
    local container_name="postgres11_prod"
    
    print_info "Testing database connections..."
    
    # Test superuser connection
    print_info "Testing superuser connection..."
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 'Superuser: ' || current_user || ' -> ' || current_database();" > /dev/null 2>&1; then
        print_status "✅ Superuser connection successful"
    else
        print_error "❌ Superuser connection failed"
        return 1
    fi
    
    # Test app user connection
    print_info "Testing application user connection..."
    if docker exec -e PGPASSWORD="$APP_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$APP_USER" -d "$APP_DATABASE" -c "SELECT 'App user: ' || current_user || ' -> ' || current_database();" > /dev/null 2>&1; then
        print_status "✅ Application user connection successful"
    else
        print_error "❌ Application user connection failed"
        return 1
    fi
    
    print_status "✅ All database connections successful"
    return 0
}

# Test SCRAM authentication
test_scram_authentication() {
    local container_name="postgres11_prod"
    
    print_info "Testing SCRAM-SHA-256 authentication..."
    
    local auth_method=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SHOW password_encryption;" 2>/dev/null || echo "unknown")
    
    if [ "$auth_method" = "scram-sha-256" ]; then
        print_status "✅ SCRAM-SHA-256 authentication active"
        return 0
    else
        print_warning "⚠️  Password encryption: $auth_method (expected: scram-sha-256)"
        return 1
    fi
}

# Test health check script
test_health_check() {
    local container_name="postgres11_prod"
    
    print_info "Testing health check script..."
    
    if docker exec "$container_name" bash -c 'bash /opt/scripts/health-check.sh' > /dev/null 2>&1; then
        print_status "✅ Health check script working"
        return 0
    else
        print_error "❌ Health check script failed"
        return 1
    fi
}

# Test backup script
test_backup_script() {
    local container_name="postgres11_prod"
    
    print_info "Testing backup script availability..."
    
    if docker exec "$container_name" bash -c 'test -x /opt/scripts/backup.sh'; then
        print_status "✅ Backup script is available and executable"
        return 0
    else
        print_error "❌ Backup script not available or not executable"
        return 1
    fi
}

# Test network connectivity
test_network_connectivity() {
    local container_name="postgres11_prod"
    local network_name="${NETWORK_NAME:-app-network}"
    
    print_info "Testing network connectivity..."
    
    # Check if container is on the expected network
    local container_networks=$(docker inspect "$container_name" --format='{{range $network, $config := .NetworkSettings.Networks}}{{$network}} {{end}}')
    
    if echo "$container_networks" | grep -q "$network_name"; then
        print_status "✅ Container is connected to network: $network_name"
        
        # Test internal connectivity by creating a temporary test container
        print_info "Testing sibling container connectivity..."
        
        local test_container="postgres_test_$(date +%s)"
        
        if docker run --rm --network "$network_name" alpine:latest \
            sh -c "apk add --no-cache postgresql-client > /dev/null 2>&1 && pg_isready -h $container_name -p 5432 -U $POSTGRES_USER" > /dev/null 2>&1; then
            print_status "✅ Sibling container connectivity working"
            return 0
        else
            print_error "❌ Sibling container connectivity failed"
            return 1
        fi
    else
        print_error "❌ Container not connected to expected network: $network_name"
        print_info "Connected networks: $container_networks"
        return 1
    fi
}

# Test data persistence
test_data_persistence() {
    local container_name="postgres11_prod"
    local test_table="test_persistence_$(date +%s)"
    
    print_info "Testing data persistence..."
    
    # Create a test table with some data
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        CREATE TABLE IF NOT EXISTS $test_table (id SERIAL PRIMARY KEY, test_data TEXT, created_at TIMESTAMP DEFAULT NOW());
        INSERT INTO $test_table (test_data) VALUES ('persistence_test_data');
    " > /dev/null 2>&1; then
        
        # Verify the data exists
        local row_count=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT COUNT(*) FROM $test_table;")
        
        if [ "$row_count" -gt 0 ]; then
            print_status "✅ Data persistence test passed"
            
            # Clean up test table
            docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP TABLE $test_table;" > /dev/null 2>&1
            return 0
        else
            print_error "❌ Data persistence test failed - no data found"
            return 1
        fi
    else
        print_error "❌ Data persistence test failed - couldn't create test table"
        return 1
    fi
}

# Test configuration
test_configuration() {
    local container_name="postgres11_prod"
    
    print_info "Testing PostgreSQL configuration..."
    
    # Test key configuration settings
    local tests=(
        "listen_addresses|*"
        "port|5432"
        "max_connections|100"
        "password_encryption|scram-sha-256"
    )
    
    local config_ok=true
    
    for test in "${tests[@]}"; do
        local setting=$(echo "$test" | cut -d'|' -f1)
        local expected=$(echo "$test" | cut -d'|' -f2)
        
        local actual=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SHOW $setting;" 2>/dev/null | tr -d ' ')
        
        if [ "$actual" = "$expected" ]; then
            print_info "✅ $setting: $actual"
        else
            print_warning "⚠️  $setting: $actual (expected: $expected)"
            config_ok=false
        fi
    done
    
    if [ "$config_ok" = true ]; then
        print_status "✅ Configuration test passed"
        return 0
    else
        print_warning "⚠️  Some configuration values are unexpected"
        return 1
    fi
}

# Test dual user setup
test_dual_user_setup() {
    local container_name="postgres11_prod"
    
    print_info "Testing dual user setup and permissions..."
    
    # Test that both users exist
    print_info "Verifying users exist..."
    local user_count=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT COUNT(*) FROM pg_roles WHERE rolname IN ('$POSTGRES_USER', '$APP_USER');" 2>/dev/null || echo "0")
    
    if [ "$user_count" -eq 2 ]; then
        print_status "✅ Both users exist in database"
    else
        print_error "❌ Missing users (found: $user_count, expected: 2)"
        return 1
    fi
    
    # Test that both databases exist
    print_info "Verifying databases exist..."
    local db_count=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d postgres -tAc "SELECT COUNT(*) FROM pg_database WHERE datname IN ('$POSTGRES_DB', '$APP_DATABASE');" 2>/dev/null || echo "0")
    
    if [ "$db_count" -eq 2 ]; then
        print_status "✅ Both databases exist"
    else
        print_error "❌ Missing databases (found: $db_count, expected: 2)"
        return 1
    fi
    
    # Test app user can create tables in app database
    print_info "Testing app user table creation permissions..."
    if docker exec -e PGPASSWORD="$APP_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$APP_USER" -d "$APP_DATABASE" -c "
        CREATE TABLE IF NOT EXISTS test_permissions (id SERIAL PRIMARY KEY, data TEXT);
        INSERT INTO test_permissions (data) VALUES ('permission_test');
        SELECT COUNT(*) FROM test_permissions;
        DROP TABLE test_permissions;
    " > /dev/null 2>&1; then
        print_status "✅ App user has proper table creation permissions"
    else
        print_error "❌ App user lacks table creation permissions"
        return 1
    fi
    
    # Test that app user cannot access superuser database
    print_info "Testing access separation..."
    if docker exec -e PGPASSWORD="$APP_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$APP_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1; then
        print_warning "⚠️  App user can access superuser database (security concern)"
    else
        print_status "✅ App user properly restricted from superuser database"
    fi
    
    # Test superuser privileges
    print_info "Testing superuser privileges..."
    local is_superuser=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT rolsuper FROM pg_roles WHERE rolname = '$POSTGRES_USER';" 2>/dev/null || echo "f")
    
    if [ "$is_superuser" = "t" ]; then
        print_status "✅ Postgres user has superuser privileges"
    else
        print_error "❌ Postgres user lacks superuser privileges"
        return 1
    fi
    
    print_status "✅ Dual user setup test passed"
    return 0
}

# Show deployment status
show_deployment_status() {
    local container_name="postgres11_prod"
    
    print_info ""
    print_status "Deployment Status Summary"
    print_status "========================="
    
    # Container information
    print_info "Container information:"
    docker ps | head -1
    docker ps | grep "$container_name" || print_warning "Container not found in running containers"
    
    # Resource usage
    print_info ""
    print_info "Resource usage:"
    docker stats "$container_name" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || print_warning "Unable to get resource stats"
    
    # Volume information
    print_info ""
    print_info "Volume information:"
    docker inspect "$container_name" | grep -A 10 '"Mounts"' | grep -E '"Source"|"Destination"' || print_warning "Unable to get volume information"
    
    # Recent logs
    print_info ""
    print_info "Recent logs (last 10 lines):"
    docker logs "$container_name" --tail 10 2>/dev/null || print_warning "Unable to get container logs"
}

# Display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -q, --quick    Quick test (basic connectivity only)"
    echo "  -f, --full     Full test suite (all tests)"
    echo "  -s, --status   Show deployment status information"
    echo "  -v, --verbose  Enable verbose output"
    echo ""
    echo "Test categories:"
    echo "  Basic:     Container status, PostgreSQL readiness, database connection"
    echo "  Security:  SCRAM authentication, configuration validation"
    echo "  Network:   Network connectivity, sibling container access"
    echo "  Storage:   Data persistence, backup script availability"
    echo "  Health:    Health check script functionality"
}

# Main execution
main() {
    local test_mode="basic"
    local show_status=false
    local verbose_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -q|--quick)
                test_mode="quick"
                shift
                ;;
            -f|--full)
                test_mode="full"
                shift
                ;;
            -s|--status)
                show_status=true
                shift
                ;;
            -v|--verbose)
                verbose_flag=true
                set -x
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_status "Starting PostgreSQL 11 deployment testing"
    print_status "=========================================="
    
    # Load environment
    load_env
    
    # Track test results
    local tests_passed=0
    local tests_failed=0
    local tests_warning=0
    
    # Define test functions based on mode
    local basic_tests=(
        "test_container_status"
        "test_postgres_ready"
        "test_database_connection"
        "test_dual_user_setup"
    )
    
    local full_tests=(
        "test_container_status"
        "test_postgres_ready"
        "test_database_connection"
        "test_scram_authentication"
        "test_health_check"
        "test_backup_script"
        "test_network_connectivity"
        "test_data_persistence"
        "test_configuration"
        "test_dual_user_setup"
    )
    
    # Select tests to run
    local tests_to_run=()
    case $test_mode in
        "quick")
            tests_to_run=("test_container_status" "test_postgres_ready")
            ;;
        "basic")
            tests_to_run=("${basic_tests[@]}")
            ;;
        "full")
            tests_to_run=("${full_tests[@]}")
            ;;
    esac
    
    print_info "Running $test_mode tests..."
    print_info ""
    
    # Run tests
    for test_func in "${tests_to_run[@]}"; do
        if $test_func; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
        echo ""
    done
    
    # Show status if requested
    if [ "$show_status" = true ]; then
        show_deployment_status
    fi
    
    # Summary
    print_info ""
    print_status "Test Results Summary"
    print_status "===================="
    print_info "Tests passed: $tests_passed"
    print_info "Tests failed: $tests_failed"
    
    if [ $tests_failed -eq 0 ]; then
        print_status "🎉 All tests passed! Deployment is healthy."
        exit 0
    else
        print_error "❌ $tests_failed test(s) failed. Please check the deployment."
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
