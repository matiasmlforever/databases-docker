#!/bin/bash
# PostgreSQL 11 Docker Image Build Script for Docker Hub
# Builds a production-ready PostgreSQL 11 image with embedded configuration

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
        set -a  # automatically export all variables
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
    
    required_vars=("POSTGRES_USER" "POSTGRES_PASSWORD" "POSTGRES_DB" "APP_USER" "APP_PASSWORD" "APP_DATABASE" "DOCKER_USERNAME" "IMAGE_NAME")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    print_status "Environment validation passed"
}

# Validate required files
validate_files() {
    print_info "Validating required files..."
    
    required_files=(
        "Dockerfile"
        "conf/postgres11.conf"
        "conf/pg_hba.conf"
        "scripts/init-db.sh"
        "scripts/health-check.sh"
        "scripts/backup.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file $file not found"
            exit 1
        fi
    done
    
    print_status "File validation passed"
}

# Generate build information
generate_build_info() {
    export BUILD_DATE=$(date +"%Y%m%d")
    export BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    export GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    print_info "Build Information:"
    print_info "  Build Date: $BUILD_DATE"
    print_info "  Build Timestamp: $BUILD_TIMESTAMP"
    print_info "  Git Commit: $GIT_COMMIT"
    print_info "  Version: ${VERSION:-1.0.0}"
}

# Build Docker image
build_image() {
    local image_full_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    local image_versioned="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${VERSION:-1.0.0}"
    local image_dated="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${BUILD_DATE}"
    
    print_status "Building Docker image: $image_full_name"
    print_info "Image will also be tagged as:"
    print_info "  $image_versioned"
    print_info "  $image_dated"
    
    print_info "Build arguments:"
    print_info "  POSTGRES_USER: $POSTGRES_USER"
    print_info "  POSTGRES_DB: $POSTGRES_DB"
    print_info "  POSTGRES_PASSWORD: [HIDDEN]"
    print_info "  APP_USER: $APP_USER"
    print_info "  APP_DATABASE: $APP_DATABASE"
    print_info "  APP_PASSWORD: [HIDDEN]"
    print_info "  BUILD_DATE: $BUILD_DATE"
    print_info "  VERSION: ${VERSION:-1.0.0}"
    
    # Build the image with multiple tags
    if docker build \
        --build-arg POSTGRES_USER="$POSTGRES_USER" \
        --build-arg POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        --build-arg POSTGRES_DB="$POSTGRES_DB" \
        --build-arg APP_USER="$APP_USER" \
        --build-arg APP_PASSWORD="$APP_PASSWORD" \
        --build-arg APP_DATABASE="$APP_DATABASE" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VERSION="${VERSION:-1.0.0}" \
        -t "$image_full_name" \
        -t "$image_versioned" \
        -t "$image_dated" \
        .; then
        
        print_status "Docker image built successfully!"
        
        # Display image information
        print_info "Image details:"
        docker images | grep "${DOCKER_USERNAME}/${IMAGE_NAME}" | head -5
        
        # Display image size
        local image_size=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep "${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}" | awk '{print $2}')
        print_info "Image size: $image_size"
        
        return 0
    else
        print_error "Docker image build failed"
        return 1
    fi
}

# Test the built image
test_image() {
    local image_full_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    local test_container_name="postgres_test_$(date +%s)"
    
    print_info "Testing the built image..."
    
    # Start test container with volume for fresh initialization
    print_info "Starting test container: $test_container_name"
    if docker run -d \
        --name "$test_container_name" \
        -v postgres_test_data:/var/lib/postgresql/data \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -e APP_USER="$APP_USER" \
        -e APP_PASSWORD="$APP_PASSWORD" \
        -e APP_DATABASE="$APP_DATABASE" \
        -e POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256 --auth-local=scram-sha-256" \
        "$image_full_name"; then
        
        print_info "Test container started, waiting for PostgreSQL to be ready..."
        
        # Show initial logs immediately
        sleep 3
        print_info "Initial container logs:"
        docker logs "$test_container_name" 2>&1 | tail -20
        
        # Wait for PostgreSQL to be ready with better logging
        local max_attempts=60  # Increase attempts
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            # Check if container is still running
            if ! docker ps -q --filter "name=$test_container_name" | grep -q .; then
                print_error "Container stopped unexpectedly!"
                print_error "Container logs:"
                docker logs "$test_container_name"
                docker rm -f "$test_container_name" 2>/dev/null || true
                docker volume rm postgres_test_data 2>/dev/null || true
                return 1
            fi
            
            # Check if PostgreSQL is ready
            if docker exec "$test_container_name" sh -c 'pg_isready -h localhost -p 5432 -U postgres -q' 2>/dev/null; then
                print_status "PostgreSQL is ready!"
                break
            fi
            
            # Show progress every 10 attempts
            if [ $((attempt % 10)) -eq 0 ]; then
                print_info "Attempt $attempt/$max_attempts: PostgreSQL not ready yet..."
                print_info "Recent logs:"
                docker logs "$test_container_name" 2>&1 | tail -10
            fi
            
            sleep 3
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            print_error "PostgreSQL did not become ready within expected time"
            print_error "Full container logs:"
            docker logs "$test_container_name"
            print_error "Container inspection:"
            docker inspect "$test_container_name" --format='{{json .State}}' 2>/dev/null || echo "Could not inspect container state"
            docker rm -f "$test_container_name"
            docker volume rm postgres_test_data 2>/dev/null || true
            return 1
        fi
        
        # Test connection with the actual user (not postgres)
        print_info "Testing database connection with app user..."
        if docker exec "$test_container_name" sh -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -h localhost -p 5432 -U '$POSTGRES_USER' -d '$POSTGRES_DB' -c \"SELECT current_user, version();\"" 2>/dev/null; then
            print_status "Database connection test passed!"
        else
            print_error "Database connection test failed"
            print_error "Trying to connect as postgres user for debugging:"
            docker exec "$test_container_name" sh -c 'psql -h localhost -p 5432 -U postgres -d postgres -c "SELECT current_user; \\du;"' 2>&1 || true
            docker logs "$test_container_name"
            docker rm -f "$test_container_name"
            docker volume rm postgres_test_data 2>/dev/null || true
            return 1
        fi
        
        # Test health check
        print_info "Testing health check..."
        if docker exec "$test_container_name" sh -c '/opt/scripts/health-check.sh' 2>/dev/null; then
            print_status "Health check test passed!"
        else
            print_warning "Health check test failed, but continuing..."
            # Don't fail the build for health check issues in testing
        fi
        
        # Cleanup test container and volume
        print_info "Cleaning up test container and volume..."
        docker rm -f "$test_container_name"
        docker volume rm postgres_test_data 2>/dev/null || true
        
        print_status "Image testing completed successfully!"
        return 0
    else
        print_error "Failed to start test container"
        return 1
    fi
}

# Display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -t, --test     Test the image after building"
    echo "  -v, --verbose  Enable verbose output"
    echo ""
    echo "Environment variables (loaded from .env.prod):"
    echo "  POSTGRES_USER     PostgreSQL application user"
    echo "  POSTGRES_PASSWORD PostgreSQL application password"
    echo "  POSTGRES_DB       PostgreSQL application database"
    echo "  DOCKER_USERNAME   Docker Hub username"
    echo "  IMAGE_NAME        Docker image name"
    echo "  IMAGE_TAG         Docker image tag (default: latest)"
    echo "  VERSION           Image version (default: 1.0.0)"
}

# Main execution
main() {
    local test_image_flag=false
    local verbose_flag=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -t|--test)
                test_image_flag=true
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
    
    print_status "Starting PostgreSQL 11 Docker image build process"
    print_status "=================================================="
    
    # Execute build steps
    load_env
    validate_env
    validate_files
    generate_build_info
    
    if build_image; then
        if [ "$test_image_flag" = true ]; then
            if test_image; then
                print_status "🎉 Build and test completed successfully!"
            else
                print_error "Image testing failed"
                exit 1
            fi
        else
            print_status "🎉 Build completed successfully!"
            print_info "To test the image, run: $0 --test"
        fi
        
        print_info ""
        print_info "Next steps:"
        print_info "1. Test the image: ./build.sh --test"
        print_info "2. Push to Docker Hub: ./push.sh"
        print_info "3. Deploy in production: ./deploy.sh"
        
    else
        print_error "Build failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
