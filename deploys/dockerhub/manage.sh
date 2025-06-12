#!/bin/bash
# PostgreSQL 11 All-in-One Management Script for Docker Hub
# Provides a unified interface for build, push, deploy, and manage operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

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

# Check if script exists and is executable
check_script() {
    local script_name="$1"
    
    if [ ! -f "$script_name" ]; then
        print_error "Script not found: $script_name"
        return 1
    fi
    
    if [ ! -x "$script_name" ]; then
        print_info "Making script executable: $script_name"
        chmod +x "$script_name"
    fi
    
    return 0
}

# Build image
cmd_build() {
    print_header "BUILDING POSTGRESQL 11 IMAGE"
    
    if check_script "./build.sh"; then
        ./build.sh "$@"
    else
        exit 1
    fi
}

# Push to Docker Hub
cmd_push() {
    print_header "PUSHING TO DOCKER HUB"
    
    if check_script "./push.sh"; then
        ./push.sh "$@"
    else
        exit 1
    fi
}

# Deploy from Docker Hub
cmd_deploy() {
    print_header "DEPLOYING FROM DOCKER HUB"
    
    if check_script "./deploy.sh"; then
        ./deploy.sh "$@"
    else
        exit 1
    fi
}

# Test deployment
cmd_test() {
    print_header "TESTING DEPLOYMENT"
    
    if check_script "./test-deployment.sh"; then
        ./test-deployment.sh "$@"
    else
        exit 1
    fi
}

# Build and push workflow
cmd_publish() {
    print_header "BUILD AND PUBLISH WORKFLOW"
    
    print_info "Step 1: Building image..."
    if ! cmd_build --test; then
        print_error "Build failed"
        exit 1
    fi
    
    print_info ""
    print_info "Step 2: Pushing to Docker Hub..."
    if ! cmd_push; then
        print_error "Push failed"
        exit 1
    fi
    
    print_status "🎉 Publish workflow completed successfully!"
}

# Full deployment workflow
cmd_full_deploy() {
    print_header "FULL DEPLOYMENT WORKFLOW"
    
    print_info "Step 1: Deploying from Docker Hub..."
    if ! cmd_deploy --test; then
        print_error "Deployment failed"
        exit 1
    fi
    
    print_info ""
    print_info "Step 2: Running comprehensive tests..."
    if ! cmd_test --full; then
        print_error "Testing failed"
        exit 1
    fi
    
    print_status "🎉 Full deployment workflow completed successfully!"
}

# Container management
cmd_logs() {
    local container_name="postgres11_prod"
    local follow_flag=""
    
    if [ "$1" = "-f" ] || [ "$1" = "--follow" ]; then
        follow_flag="-f"
        shift
    fi
    
    print_header "CONTAINER LOGS"
    
    if docker ps | grep -q "$container_name"; then
        docker logs $follow_flag "$container_name" "$@"
    else
        print_error "Container $container_name is not running"
        exit 1
    fi
}

cmd_connect() {
    local container_name="postgres11_prod"
    local user_type="${1:-app}"  # Default to app user
    
    print_header "CONNECTING TO DATABASE"
    
    # Load environment to get connection details
    if [ -f ".env.prod" ]; then
        source .env.prod
    fi
    
    if docker ps | grep -q "$container_name"; then
        case "$user_type" in
            "admin"|"postgres"|"superuser")
                print_info "Connecting as superuser: ${POSTGRES_USER:-postgres}"
                print_info "Database: ${POSTGRES_DB:-postgres}"
                docker exec -it "$container_name" psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}"
                ;;
            "app"|"application"|*)
                print_info "Connecting as application user: ${APP_USER:-app_user}"
                print_info "Database: ${APP_DATABASE:-app_db}"
                docker exec -it "$container_name" psql -U "${APP_USER:-app_user}" -d "${APP_DATABASE:-app_db}"
                ;;
        esac
    else
        print_error "Container $container_name is not running"
        exit 1
    fi
}

cmd_shell() {
    local container_name="postgres11_prod"
    
    print_header "ACCESSING CONTAINER SHELL"
    
    if docker ps | grep -q "$container_name"; then
        docker exec -it "$container_name" bash
    else
        print_error "Container $container_name is not running"
        exit 1
    fi
}

cmd_backup() {
    local container_name="postgres11_prod"
    
    print_header "CREATING BACKUP"
    
    if docker ps | grep -q "$container_name"; then
        docker exec "$container_name" bash -c 'bash /opt/scripts/backup.sh'
    else
        print_error "Container $container_name is not running"
        exit 1
    fi
}

cmd_status() {
    print_header "DEPLOYMENT STATUS"
    
    local container_name="postgres11_prod"
    local network_name="app-network"
    local volume_name="postgres11_prod_data"
    
    # Container status
    print_info "Container Status:"
    if docker ps | grep -q "$container_name"; then
        docker ps | head -1
        docker ps | grep "$container_name"
        print_status "✅ Container is running"
    else
        if docker ps -a | grep -q "$container_name"; then
            docker ps -a | grep "$container_name"
            print_warning "⚠️  Container exists but is not running"
        else
            print_error "❌ Container does not exist"
        fi
    fi
    
    echo ""
    
    # Network status
    print_info "Network Status:"
    if docker network ls | grep -q "$network_name"; then
        print_status "✅ Network $network_name exists"
        docker network ls | grep "$network_name"
    else
        print_error "❌ Network $network_name does not exist"
    fi
    
    echo ""
    
    # Volume status
    print_info "Volume Status:"
    if docker volume ls | grep -q "$volume_name"; then
        print_status "✅ Volume $volume_name exists"
        docker volume ls | grep "$volume_name"
    else
        print_error "❌ Volume $volume_name does not exist"
    fi
    
    echo ""
    
    # Quick health check if container is running
    if docker ps | grep -q "$container_name"; then
        print_info "Health Check:"
        if docker exec "$container_name" bash -c 'bash /opt/scripts/health-check.sh' > /dev/null 2>&1; then
            print_status "✅ Health check passed"
        else
            print_error "❌ Health check failed"
        fi
    fi
}

cmd_stop() {
    local container_name="postgres11_prod"
    
    print_header "STOPPING CONTAINER"
    
    if docker ps | grep -q "$container_name"; then
        print_info "Stopping container: $container_name"
        docker stop "$container_name"
        print_status "✅ Container stopped"
    else
        print_warning "Container $container_name is not running"
    fi
}

cmd_start() {
    local container_name="postgres11_prod"
    
    print_header "STARTING CONTAINER"
    
    if docker ps -a | grep -q "$container_name"; then
        if docker ps | grep -q "$container_name"; then
            print_warning "Container $container_name is already running"
        else
            print_info "Starting container: $container_name"
            docker start "$container_name"
            print_status "✅ Container started"
        fi
    else
        print_error "Container $container_name does not exist"
        print_info "Use 'deploy' command to create and start the container"
        exit 1
    fi
}

cmd_restart() {
    print_header "RESTARTING CONTAINER"
    
    cmd_stop
    echo ""
    cmd_start
}

cmd_remove() {
    local container_name="postgres11_prod"
    local network_name="app-network"
    local volume_name="postgres11_prod_data"
    
    print_header "REMOVING DEPLOYMENT"
    
    print_warning "This will remove the container, network, and optionally the data volume."
    print_warning "Data will be PERMANENTLY LOST if you remove the volume!"
    echo ""
    read -p "Remove container? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if docker ps -a | grep -q "$container_name"; then
            print_info "Stopping and removing container: $container_name"
            docker rm -f "$container_name"
            print_status "✅ Container removed"
        else
            print_info "Container $container_name does not exist"
        fi
    fi
    
    echo ""
    read -p "Remove network? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if docker network ls | grep -q "$network_name"; then
            print_info "Removing network: $network_name"
            docker network rm "$network_name" 2>/dev/null || print_warning "Network may be in use by other containers"
            print_status "✅ Network removal attempted"
        else
            print_info "Network $network_name does not exist"
        fi
    fi
    
    echo ""
    read -p "Remove data volume? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if docker volume ls | grep -q "$volume_name"; then
            print_warning "⚠️  This will PERMANENTLY DELETE all database data!"
            read -p "Are you absolutely sure? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_info "Removing volume: $volume_name"
                docker volume rm "$volume_name"
                print_status "✅ Volume removed"
            else
                print_info "Volume removal cancelled"
            fi
        else
            print_info "Volume $volume_name does not exist"
        fi
    fi
}

# Show environment information
cmd_env() {
    print_header "ENVIRONMENT INFORMATION"
    
    if [ -f ".env.prod" ]; then
        print_info "Production environment (.env.prod):"
        echo ""
        cat .env.prod | grep -v '^#' | grep -v '^$' | while IFS= read -r line; do
            if [[ $line == *"PASSWORD"* ]]; then
                key=$(echo "$line" | cut -d'=' -f1)
                echo "  $key=[HIDDEN]"
            else
                echo "  $line"
            fi
        done
    else
        print_error ".env.prod file not found"
    fi
    
    echo ""
    print_info "Docker information:"
    echo "  Docker version: $(docker --version)"
    echo "  Available images:"
    docker images | grep postgres11-prod || print_info "  No postgres11-prod images found"
}

# Display main help
show_help() {
    echo "PostgreSQL 11 Docker Hub Management Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Build & Publish Commands:"
    echo "  build          Build the Docker image locally"
    echo "  push           Push the image to Docker Hub"
    echo "  publish        Build and push workflow"
    echo ""
    echo "Deployment Commands:"
    echo "  deploy         Deploy from Docker Hub"
    echo "  full-deploy    Deploy and run comprehensive tests"
    echo "  test           Test existing deployment"
    echo ""
    echo "Container Management:"
    echo "  start          Start the container"
    echo "  stop           Stop the container"
    echo "  restart        Restart the container"
    echo "  status         Show deployment status"
    echo "  remove         Remove deployment (container, network, volume)"
    echo ""
    echo "Database Operations:"
    echo "  connect [user] Connect to database (psql)"
    echo "                 user options: app (default), admin/postgres"
    echo "                 Examples:"
    echo "                   ./manage.sh connect        # Connect as app user"
    echo "                   ./manage.sh connect app    # Connect as app user"
    echo "                   ./manage.sh connect admin  # Connect as superuser"
    echo "  shell          Access container shell"
    echo "  logs           View container logs"
    echo "  backup         Create database backup"
    echo ""
    echo "Information:"
    echo "  env            Show environment configuration"
    echo "  help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 publish              # Build and push to Docker Hub"
    echo "  $0 full-deploy          # Deploy and test"
    echo "  $0 logs -f              # Follow container logs"
    echo "  $0 test --full          # Run full test suite"
    echo "  $0 deploy --force       # Force deployment without confirmation"
    echo ""
    echo "For command-specific help, use: $0 <command> --help"
}

# Main execution
main() {
    # Check if we're in the right directory
    if [ ! -f ".env.prod" ]; then
        print_error "This script must be run from the deploys/dockerhub directory"
        print_info "Expected file: .env.prod"
        exit 1
    fi
    
    # Ensure scripts are executable
    local scripts=("build.sh" "push.sh" "deploy.sh" "test-deployment.sh")
    for script in "${scripts[@]}"; do
        if [ -f "$script" ] && [ ! -x "$script" ]; then
            chmod +x "$script"
        fi
    done
    
    # Parse command
    local command="${1:-help}"
    shift || true
    
    case $command in
        build)
            cmd_build "$@"
            ;;
        push)
            cmd_push "$@"
            ;;
        publish)
            cmd_publish "$@"
            ;;
        deploy)
            cmd_deploy "$@"
            ;;
        full-deploy)
            cmd_full_deploy "$@"
            ;;
        test)
            cmd_test "$@"
            ;;
        start)
            cmd_start "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        restart)
            cmd_restart "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        remove)
            cmd_remove "$@"
            ;;
        connect)
            cmd_connect "$@"
            ;;
        shell)
            cmd_shell "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;
        backup)
            cmd_backup "$@"
            ;;
        env)
            cmd_env "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
