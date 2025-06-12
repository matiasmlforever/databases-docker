#!/bin/bash
# PostgreSQL 11 Production Deployment Script
# Deploys the image from Docker Hub for production use with sibling container access

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

# Validate environment
validate_env() {
    print_info "Validating environment variables..."
    
    required_vars=("DOCKER_USERNAME" "IMAGE_NAME" "POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    print_status "Environment validation passed"
}

# Create Docker network for sibling containers
create_network() {
    local network_name="${NETWORK_NAME:-app-network}"
    
    print_info "Creating Docker network for sibling containers: $network_name"
    
    if docker network ls | grep -q "$network_name"; then
        print_info "Network $network_name already exists"
    else
        if docker network create --driver bridge "$network_name"; then
            print_status "Network $network_name created successfully"
        else
            print_error "Failed to create network $network_name"
            exit 1
        fi
    fi
    
    # Show network details
    print_info "Network details:"
    docker network inspect "$network_name" | grep -E "(Name|Subnet|Gateway)" || true
}

# Create volume for data persistence
create_volume() {
    local volume_name="postgres11_prod_data"
    
    print_info "Creating Docker volume for data persistence: $volume_name"
    
    if docker volume ls | grep -q "$volume_name"; then
        print_info "Volume $volume_name already exists"
    else
        if docker volume create "$volume_name"; then
            print_status "Volume $volume_name created successfully"
        else
            print_error "Failed to create volume $volume_name"
            exit 1
        fi
    fi
    
    # Show volume details
    print_info "Volume details:"
    docker volume inspect "$volume_name" | grep -E "(Name|Mountpoint)" || true
}

# Stop and remove existing container
cleanup_existing() {
    local container_name="postgres11_prod"
    
    print_info "Cleaning up existing container: $container_name"
    
    if docker ps -a | grep -q "$container_name"; then
        print_info "Stopping existing container..."
        docker stop "$container_name" 2>/dev/null || true
        
        print_info "Removing existing container..."
        docker rm "$container_name" 2>/dev/null || true
        
        print_status "Existing container cleaned up"
    else
        print_info "No existing container found"
    fi
}

# Pull latest image from Docker Hub
pull_image() {
    local image_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    print_info "Pulling latest image from Docker Hub: $image_name"
    
    if docker pull "$image_name"; then
        print_status "Image pulled successfully"
        
        # Show image details
        print_info "Image details:"
        docker images | grep "${DOCKER_USERNAME}/${IMAGE_NAME}" | head -3
    else
        print_error "Failed to pull image from Docker Hub"
        exit 1
    fi
}

# Deploy PostgreSQL container
deploy_container() {
    local container_name="postgres11_prod"
    local image_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    local network_name="${NETWORK_NAME:-app-network}"
    local volume_name="postgres11_prod_data"
    
    print_status "Deploying PostgreSQL container: $container_name"
    
    print_info "Deployment configuration:"
    print_info "  Container name: $container_name"
    print_info "  Image: $image_name"
    print_info "  Network: $network_name"
    print_info "  Volume: $volume_name"
    print_info "  User: $POSTGRES_USER"
    print_info "  Database: $POSTGRES_DB"
    print_info "  Port: ${POSTGRES_PORT:-5432} (internal only)"
    
    # Deploy container
    if docker run -d \
        --name "$container_name" \
        --network "$network_name" \
        --restart "${RESTART_POLICY:-unless-stopped}" \
        -v "$volume_name:/var/lib/postgresql/data" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -e APP_USER="$APP_USER" \
        -e APP_PASSWORD="$APP_PASSWORD" \
        -e APP_DATABASE="$APP_DATABASE" \
        -e PGUSER="$POSTGRES_USER" \
        --health-cmd="pg_isready -h localhost -p 5432 -U $POSTGRES_USER" \
        --health-interval=30s \
        --health-timeout=10s \
        --health-start-period=60s \
        --health-retries=3 \
        "$image_name"; then
        
        print_status "Container deployed successfully!"
        return 0
    else
        print_error "Failed to deploy container"
        return 1
    fi
}

# Wait for PostgreSQL to be ready
wait_for_ready() {
    local container_name="postgres11_prod"
    local max_attempts=60
    local attempt=1
    
    print_info "Waiting for PostgreSQL to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker exec "$container_name" pg_isready -h localhost -p 5432 -U "$POSTGRES_USER" -q 2>/dev/null; then
            print_status "PostgreSQL is ready!"
            return 0
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            print_info "Attempt $attempt/$max_attempts: Still waiting for PostgreSQL..."
        fi
        
        sleep 2
        ((attempt++))
    done
    
    print_error "PostgreSQL did not become ready within expected time"
    print_info "Container logs:"
    docker logs "$container_name" --tail 20
    return 1
}

# Test the deployment
test_deployment() {
    local container_name="postgres11_prod"
    
    print_info "Testing deployment..."
    
    # Test database connection
    print_info "Testing database connection..."
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" > /dev/null 2>&1; then
        print_status "✅ Database connection test passed"
    else
        print_error "❌ Database connection test failed"
        return 1
    fi
    
    # Test app user connection
    print_info "Testing app user connection..."
    if docker exec -e PGPASSWORD="$APP_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$APP_USER" -d "$APP_DATABASE" -c "SELECT version();" > /dev/null 2>&1; then
        print_status "✅ App user connection test passed"
    else
        print_error "❌ App user connection test failed"
        return 1
    fi
    
    # Test health check
    print_info "Testing health check..."
    if docker exec "$container_name" bash -c 'bash /opt/scripts/health-check.sh' > /dev/null 2>&1; then
        print_status "✅ Health check test passed"
    else
        print_error "❌ Health check test failed"
        return 1
    fi
    
    # Test SCRAM authentication
    print_info "Testing SCRAM-SHA-256 authentication..."
    if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$container_name" psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SHOW password_encryption;" | grep -q "scram-sha-256"; then
        print_status "✅ SCRAM-SHA-256 authentication verified"
    else
        print_warning "⚠️  SCRAM-SHA-256 authentication check inconclusive"
    fi
    
    print_status "✅ Deployment testing completed successfully!"
    return 0
}

# Show deployment information
show_deployment_info() {
    local container_name="postgres11_prod"
    local network_name="${NETWORK_NAME:-app-network}"
    
    print_info ""
    print_status "Deployment Information"
    print_status "======================"
    
    # Container status
    print_info "Container status:"
    docker ps | grep "$container_name" || print_warning "Container not found in running containers"
    
    # Container health
    print_info ""
    print_info "Container health:"
    docker inspect "$container_name" | grep -A 5 '"Health"' | grep -E '"Status"|"Log"' || print_info "Health status not available"
    
    # Network information
    print_info ""
    print_info "Network configuration:"
    print_info "  Container name: $container_name"
    print_info "  Network: $network_name"
    print_info "  Internal port: 5432"
    print_info "  External access: DISABLED (for security)"
    
    # Connection information for sibling containers
    print_info ""
    print_info "Connection information for sibling containers:"
    print_info "  Host: $container_name"
    print_info "  Port: 5432"
    print_info "  Network: $network_name"
    print_info ""
    print_info "  Superuser (admin tasks):"
    print_info "    Database: $POSTGRES_DB"
    print_info "    User: $POSTGRES_USER"
    print_info "    Password: [CONFIGURED]"
    print_info ""
    print_info "  Application user (recommended for apps):"
    print_info "    Database: $APP_DATABASE"
    print_info "    User: $APP_USER"
    print_info "    Password: [CONFIGURED]"
    
    # Example Docker Compose configuration
    print_info ""
    print_info "Example sibling container configuration (docker-compose.yml):"
    echo "  services:"
    echo "    your-app:"
    echo "      image: your-app:latest"
    echo "      networks:"
    echo "        - $network_name"
    echo "      environment:"
    echo "        # Use application user - recommended"
    echo "        DB_HOST: $container_name"
    echo "        DB_PORT: 5432"
    echo "        DB_NAME: $APP_DATABASE"
    echo "        DB_USER: $APP_USER"
    echo "        DB_PASSWORD: \${DB_PASSWORD}"
    echo "      depends_on:"
    echo "        - $container_name"
    echo ""
    echo "  networks:"
    echo "    $network_name:"
    echo "      external: true"
}

# Show management commands
show_management_commands() {
    local container_name="postgres11_prod"
    
    print_info ""
    print_status "Management Commands"
    print_status "==================="
    print_info "View logs:           docker logs $container_name"
    print_info "View live logs:      docker logs -f $container_name"
    print_info ""
    print_info "Connect to databases:"
    print_info "  Admin postgres:    docker exec -it $container_name psql -U $POSTGRES_USER -d $POSTGRES_DB"
    print_info "  App user:          docker exec -it $container_name psql -U $APP_USER -d $APP_DATABASE"
    print_info ""
    print_info "Utilities:"
    print_info "  Run backup:        docker exec $container_name /opt/scripts/backup.sh"
    print_info "  Health check:      docker exec $container_name /opt/scripts/health-check.sh"
    print_info "  Container shell:   docker exec -it $container_name bash"
    print_info ""
    print_info "Container control:"
    print_info "  Stop container:    docker stop $container_name"
    print_info "  Start container:   docker start $container_name"
    print_info "  Remove deployment: docker stop $container_name && docker rm $container_name"
}

# Display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Force deployment - skip confirmations"
    echo "  -t, --test     Run deployment tests after deployment"
    echo "  -v, --verbose  Enable verbose output"
    echo ""
    echo "Environment variables - loaded from .env.prod:"
    echo "  DOCKER_USERNAME   Docker Hub username"
    echo "  IMAGE_NAME        Docker image name"
    echo "  IMAGE_TAG         Docker image tag - default: latest"
    echo "  POSTGRES_USER     PostgreSQL application user"
    echo "  POSTGRES_PASSWORD PostgreSQL application password"
    echo "  POSTGRES_DB       PostgreSQL application database"
    echo "  NETWORK_NAME      Docker network name - default: app-network"
    echo "  RESTART_POLICY    Container restart policy - default: unless-stopped"
}

# Main execution
main() {
    local force_flag=false
    local test_flag=false
    local verbose_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                force_flag=true
                shift
                ;;
            -t|--test)
                test_flag=true
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
    
    print_status "Starting PostgreSQL 11 production deployment"
    print_status "============================================="
    
    # Confirmation prompt (unless forced)
    if [ "$force_flag" = false ]; then
        echo ""
        print_warning "This will deploy PostgreSQL 11 in production mode."
        print_warning "Any existing 'postgres11_prod' container will be replaced."
        echo ""
        read -p "Do you want to continue? y/N: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    load_env
    validate_env
    create_network
    create_volume
    cleanup_existing
    pull_image
    
    if deploy_container; then
        if wait_for_ready; then
            if [ "$test_flag" = true ]; then
                if test_deployment; then
                    show_deployment_info
                    show_management_commands
                    print_status "🎉 Deployment and testing completed successfully!"
                else
                    print_error "Deployment testing failed"
                    exit 1
                fi
            else
                show_deployment_info
                show_management_commands
                print_status "🎉 Deployment completed successfully!"
                print_info "To test the deployment, run: $0 --test"
            fi
        else
            print_error "PostgreSQL failed to become ready"
            exit 1
        fi
    else
        print_error "Deployment failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
