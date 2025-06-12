#!/bin/bash
# PostgreSQL 11 Docker Hub Push Script
# Pushes the built image to Docker Hub with multiple tags

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
    
    required_vars=("DOCKER_USERNAME" "IMAGE_NAME")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    print_status "Environment validation passed"
}

# Check if Docker is logged in
check_docker_login() {
    print_info "Checking Docker Hub authentication..."
    
    if ! docker info | grep -q "Username: ${DOCKER_USERNAME}"; then
        print_warning "Not logged in to Docker Hub as ${DOCKER_USERNAME}"
        print_info "Attempting to log in..."
        
        if ! docker login; then
            print_error "Docker Hub login failed"
            print_info "Please run: docker login"
            exit 1
        fi
    fi
    
    print_status "Docker Hub authentication verified"
}

# Verify image exists locally
verify_image_exists() {
    local image_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    print_info "Verifying local image exists: $image_name"
    
    if ! docker image inspect "$image_name" > /dev/null 2>&1; then
        print_error "Local image not found: $image_name"
        print_info "Please build the image first: ./build.sh"
        exit 1
    fi
    
    print_status "Local image verified"
}

# Get image tags to push
get_image_tags() {
    local base_name="${DOCKER_REGISTRY}/${DOCKER_USERNAME}/${IMAGE_NAME}"
    
    # Get all local tags for this image
    local tags=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${DOCKER_USERNAME}/${IMAGE_NAME}:" | sort)
    
    if [ -z "$tags" ]; then
        print_error "No local images found for ${DOCKER_USERNAME}/${IMAGE_NAME}"
        exit 1
    fi
    
    echo "$tags"
}

# Push images to Docker Hub
push_images() {
    local tags=$(get_image_tags)
    local push_success=true
    
    print_status "Pushing images to Docker Hub..."
    print_info "Tags to push:"
    echo "$tags" | sed 's/^/  /'
    
    # Push each tag
    while IFS= read -r tag; do
        if [ -n "$tag" ]; then
            print_info "Pushing: $tag"
            
            if docker push "$tag"; then
                print_status "✅ Successfully pushed: $tag"
            else
                print_error "❌ Failed to push: $tag"
                push_success=false
            fi
        fi
    done <<< "$tags"
    
    if [ "$push_success" = true ]; then
        print_status "🎉 All images pushed successfully!"
        return 0
    else
        print_error "Some images failed to push"
        return 1
    fi
}

# Verify pushed images
verify_pushed_images() {
    print_info "Verifying pushed images on Docker Hub..."
    
    local image_base="${DOCKER_USERNAME}/${IMAGE_NAME}"
    local main_tag="${IMAGE_TAG:-latest}"
    
    print_info "Pulling image to verify: ${image_base}:${main_tag}"
    
    # Try to pull the main tag to verify it's available
    if docker pull "${image_base}:${main_tag}" > /dev/null 2>&1; then
        print_status "✅ Image successfully available on Docker Hub"
        
        # Show image info
        print_info "Pushed image details:"
        docker images | grep "${image_base}" | head -3
        
        return 0
    else
        print_error "❌ Failed to verify image on Docker Hub"
        return 1
    fi
}

# Display Docker Hub information
show_docker_hub_info() {
    local image_base="${DOCKER_USERNAME}/${IMAGE_NAME}"
    
    print_info ""
    print_status "Docker Hub Information"
    print_status "======================"
    print_info "Repository: https://hub.docker.com/r/${image_base}"
    print_info "Pull command: docker pull ${image_base}:${IMAGE_TAG:-latest}"
    print_info ""
    print_info "Available tags:"
    get_image_tags | sed 's/^/  docker pull /'
}

# Clean up local test pulls
cleanup() {
    local image_base="${DOCKER_USERNAME}/${IMAGE_NAME}"
    local main_tag="${IMAGE_TAG:-latest}"
    
    print_info "Cleaning up verification pull..."
    docker rmi "${image_base}:${main_tag}" > /dev/null 2>&1 || true
}

# Display usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Force push even if verification fails"
    echo "  -v, --verbose  Enable verbose output"
    echo ""
    echo "Environment variables (loaded from .env.prod):"
    echo "  DOCKER_USERNAME   Docker Hub username"
    echo "  IMAGE_NAME        Docker image name"
    echo "  IMAGE_TAG         Docker image tag (default: latest)"
    echo "  DOCKER_REGISTRY   Docker registry (default: docker.io)"
}

# Main execution
main() {
    local force_flag=false
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
    
    print_status "Starting Docker Hub push process"
    print_status "================================"
    
    # Execute push steps
    load_env
    validate_env
    check_docker_login
    verify_image_exists
    
    if push_images; then
        if [ "$force_flag" = false ]; then
            if verify_pushed_images; then
                cleanup
                show_docker_hub_info
                print_status "🎉 Push and verification completed successfully!"
            else
                print_error "Push verification failed"
                exit 1
            fi
        else
            show_docker_hub_info
            print_status "🎉 Push completed (verification skipped due to --force)"
        fi
        
        print_info ""
        print_info "Next steps:"
        print_info "1. Deploy in production: ./deploy.sh"
        print_info "2. Test deployment: ./test-deployment.sh"
        
    else
        print_error "Push failed"
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"
