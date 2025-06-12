#!/bin/bash
# filepath: e:\DEV\databases-docker\deploys\dockerhub\debug-test.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Load environment
if [ -f ".env.prod" ]; then
    source .env.prod
else
    print_error ".env.prod not found"
    exit 1
fi

image_full_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
test_container_name="postgres_debug_test"

print_info "Starting debug test for image: $image_full_name"

# Cleanup any existing test container
docker rm -f "$test_container_name" 2>/dev/null || true
docker volume rm postgres_debug_data 2>/dev/null || true

print_info "Starting container with detailed logging..."

# Start container with debug environment
docker run -d \
    --name "$test_container_name" \
    -v postgres_debug_data:/var/lib/postgresql/data \
    -e POSTGRES_USER="$POSTGRES_USER" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    -e POSTGRES_DB="$POSTGRES_DB" \
    -e POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256 --auth-local=scram-sha-256" \
    -e POSTGRES_HOST_AUTH_METHOD=scram-sha-256 \
    "$image_full_name"

print_info "Container started, monitoring logs for 30 seconds..."

# Monitor logs for 30 seconds
timeout 30s docker logs -f "$test_container_name" 2>&1 || true

print_info "Checking container status..."
docker ps -a | grep "$test_container_name"

print_info "Checking if PostgreSQL process is running..."
docker exec "$test_container_name" ps aux | grep postgres || true

print_info "Checking PostgreSQL readiness..."
docker exec "$test_container_name" pg_isready -h localhost -p 5432 -U postgres || true

print_info "Checking data directory contents..."
docker exec "$test_container_name" ls -la /var/lib/postgresql/data/ || true

print_info "Checking if initialization scripts ran..."
docker exec "$test_container_name" ls -la /docker-entrypoint-initdb.d/ || true

print_info "Checking custom initialization flag..."
docker exec "$test_container_name" ls -la /var/lib/postgresql/data/custom_init_completed || true

print_info "Getting final logs..."
docker logs "$test_container_name" 2>&1 | tail -50

# Cleanup
print_info "Cleaning up..."
docker rm -f "$test_container_name"
docker volume rm postgres_debug_data 2>/dev/null || true

print_status "Debug test completed!"