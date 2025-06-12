#!/bin/bash
# PostgreSQL 11 Complete Cleanup Script
# Removes all containers, images, volumes, and networks related to this PostgreSQL instance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        print_warning ".env.prod file not found, using default values"
        POSTGRES_USER=${POSTGRES_USER:-postgres}
        APP_USER=${APP_USER:-app_user}
        IMAGE_NAME=${IMAGE_NAME:-amigo-postgres11-prod}
        DOCKER_USERNAME=${DOCKER_USERNAME:-matiasmlforever}
        NETWORK_NAME=${NETWORK_NAME:-app-network}
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    print_warning "⚠️  This will PERMANENTLY remove the following:"
    echo "   • Container: postgres11_prod"
    echo "   • Volume: postgres11_prod_data (ALL DATABASE DATA WILL BE LOST)"
    echo "   • Images: $DOCKER_USERNAME/$IMAGE_NAME:* and postgres:11-bullseye"
    echo "   • Network: $NETWORK_NAME (if no other containers are using it)"
    echo ""
    print_error "⚠️  ALL DATA WILL BE PERMANENTLY LOST! ⚠️"
    echo ""
    
    if [ "$1" != "-f" ] && [ "$1" != "--force" ]; then
        read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation
        if [ "$confirmation" != "yes" ]; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
    else
        print_warning "Force mode enabled - proceeding without confirmation"
    fi
}

# Stop and remove containers
cleanup_containers() {
    print_info "Cleaning up containers..."
    
    # Stop and remove the main container
    if docker ps -a | grep -q "postgres11_prod"; then
        print_info "Stopping container: postgres11_prod"
        docker stop postgres11_prod 2>/dev/null || true
        
        print_info "Removing container: postgres11_prod"
        docker rm postgres11_prod 2>/dev/null || true
        print_status "✅ Container postgres11_prod removed"
    else
        print_info "Container postgres11_prod not found"
    fi
    
    # Remove any other containers using our image
    local containers=$(docker ps -a --filter="ancestor=$DOCKER_USERNAME/$IMAGE_NAME" --format="{{.Names}}" 2>/dev/null || true)
    if [ -n "$containers" ]; then
        print_info "Found additional containers using our image:"
        echo "$containers"
        for container in $containers; do
            print_info "Stopping and removing container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        done
    fi
}

# Remove volumes
cleanup_volumes() {
    print_info "Cleaning up volumes..."
    
    if docker volume ls | grep -q "postgres11_prod_data"; then
        print_warning "Removing volume: postgres11_prod_data (ALL DATA WILL BE LOST)"
        docker volume rm postgres11_prod_data 2>/dev/null || true
        print_status "✅ Volume postgres11_prod_data removed"
    else
        print_info "Volume postgres11_prod_data not found"
    fi
    
    # Remove any other postgres-related volumes
    local postgres_volumes=$(docker volume ls --filter="name=postgres" --format="{{.Name}}" 2>/dev/null || true)
    if [ -n "$postgres_volumes" ]; then
        print_info "Found additional PostgreSQL volumes:"
        echo "$postgres_volumes"
        for volume in $postgres_volumes; do
            print_warning "Removing volume: $volume"
            docker volume rm "$volume" 2>/dev/null || true
        done
    fi
}

# Remove images
cleanup_images() {
    print_info "Cleaning up images..."
    
    # Remove our custom image
    local our_images=$(docker images --filter="reference=$DOCKER_USERNAME/$IMAGE_NAME" --format="{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [ -n "$our_images" ]; then
        for image in $our_images; do
            print_info "Removing image: $image"
            docker rmi "$image" 2>/dev/null || true
        done
        print_status "✅ Custom PostgreSQL images removed"
    else
        print_info "No custom PostgreSQL images found"
    fi
    
    # Remove base postgres image
    if docker images | grep -q "postgres.*11-bullseye"; then
        print_info "Removing base image: postgres:11-bullseye"
        docker rmi postgres:11-bullseye 2>/dev/null || true
        print_status "✅ Base PostgreSQL image removed"
    else
        print_info "Base PostgreSQL image not found"
    fi
}

# Remove network (only if no other containers are using it)
cleanup_network() {
    print_info "Cleaning up network..."
    
    if docker network ls | grep -q "$NETWORK_NAME"; then
        # Check if any containers are still using the network
        local network_containers=$(docker network inspect "$NETWORK_NAME" --format='{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)
        
        if [ -z "$network_containers" ]; then
            print_info "Removing network: $NETWORK_NAME"
            docker network rm "$NETWORK_NAME" 2>/dev/null || true
            print_status "✅ Network $NETWORK_NAME removed"
        else
            print_warning "Network $NETWORK_NAME is still in use by: $network_containers"
            print_info "Skipping network removal"
        fi
    else
        print_info "Network $NETWORK_NAME not found"
    fi
}

# Clean up dangling resources
cleanup_dangling() {
    print_info "Cleaning up dangling resources..."
    
    # Remove dangling images
    local dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null || true)
    if [ -n "$dangling_images" ]; then
        print_info "Removing dangling images"
        docker rmi $dangling_images 2>/dev/null || true
    fi
    
    # Remove unused volumes
    print_info "Removing unused volumes"
    docker volume prune -f 2>/dev/null || true
    
    print_status "✅ Dangling resources cleaned"
}

# Show final status
show_cleanup_status() {
    print_info ""
    print_status "Cleanup Status Summary"
    print_status "======================"
    
    print_info "Remaining PostgreSQL containers:"
    docker ps -a | grep -E "(CONTAINER|postgres)" || print_info "No PostgreSQL containers found"
    
    print_info ""
    print_info "Remaining PostgreSQL images:"
    docker images | grep -E "(REPOSITORY|postgres)" || print_info "No PostgreSQL images found"
    
    print_info ""
    print_info "Remaining PostgreSQL volumes:"
    docker volume ls | grep -E "(DRIVER|postgres)" || print_info "No PostgreSQL volumes found"
    
    print_info ""
    print_info "Network status:"
    docker network ls | grep -E "(NETWORK|$NETWORK_NAME)" || print_info "Network $NETWORK_NAME not found"
}

# Display usage information
show_usage() {
    echo "PostgreSQL 11 Complete Cleanup Script"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Force cleanup without confirmation"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "This script will remove:"
    echo "  • All PostgreSQL containers (postgres11_prod and others)"
    echo "  • All PostgreSQL volumes (postgres11_prod_data and others)"
    echo "  • All custom PostgreSQL images ($DOCKER_USERNAME/$IMAGE_NAME)"
    echo "  • Base PostgreSQL image (postgres:11-bullseye)"
    echo "  • Network ($NETWORK_NAME) if not in use"
    echo "  • Dangling Docker resources"
    echo ""
    echo "⚠️  WARNING: ALL DATABASE DATA WILL BE PERMANENTLY LOST!"
}

# Main execution
main() {
    local force_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_mode=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_status "PostgreSQL 11 Complete Cleanup"
    print_status "==============================="
    
    # Load environment
    load_env
    
    # Confirm cleanup
    if [ "$force_mode" = true ]; then
        confirm_cleanup "--force"
    else
        confirm_cleanup
    fi
    
    print_info ""
    print_status "Starting cleanup process..."
    
    # Execute cleanup steps
    cleanup_containers
    cleanup_volumes
    cleanup_images
    cleanup_network
    cleanup_dangling
    
    # Show final status
    show_cleanup_status
    
    print_info ""
    print_status "🎉 Cleanup completed successfully!"
    print_info "All PostgreSQL resources have been removed."
}

# Execute main function with all arguments
main "$@"
