#!/bin/bash
# Simple PostgreSQL 11 Docker Image Build Script
# Just builds the image without complex testing

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_status() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Load environment
if [ -f ".env.prod" ]; then
    source .env.prod
else
    print_error ".env.prod not found"
    exit 1
fi

# Validate required variables
if [ -z "$DOCKER_USERNAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ]; then
    print_error "Missing required environment variables"
    exit 1
fi

# Set build info
export BUILD_DATE=$(date +"%Y%m%d")
export VERSION=${VERSION:-"1.0.0"}

# Image name
image_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

print_info "Building PostgreSQL 11 Docker Image"
print_info "Image: $image_name"
print_info "User: $POSTGRES_USER"
print_info "Database: $POSTGRES_DB"

# Build the image
print_info "Starting Docker build..."

if docker build \
    --build-arg POSTGRES_USER="$POSTGRES_USER" \
    --build-arg POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    --build-arg POSTGRES_DB="$POSTGRES_DB" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VERSION="$VERSION" \
    -t "$image_name" \
    .; then
    
    print_status "Docker image built successfully!"
    
    # Show image info
    print_info "Image details:"
    docker images "$image_name"
    
    print_info ""
    print_status "Build completed!"
    print_info "Image: $image_name"
    print_info ""
    print_info "Next steps:"
    print_info "1. Test: docker run -d --name test-postgres $image_name"
    print_info "2. Push: ./push.sh"
    print_info "3. Deploy: ./deploy.sh"
    
else
    print_error "Docker build failed"
    exit 1
fi
