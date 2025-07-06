#!/bin/bash

# Self-Healing Infrastructure Deployment Script
# This script automates the deployment of the entire self-healing infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # Check docker
    if ! command -v docker &> /dev/null; then
        print_error "docker is not installed or not in PATH"
        exit 1
    fi
    
    print_success "All prerequisites are satisfied"
}

# Function to build Docker images
build_images() {
    print_status "Building Docker images..."
    
    # Build operator image
    print_status "Building self-healing operator..."
    docker build -t your-repo/self-healing-operator:latest ./operator
    
    # Build Node.js app image
    print_status "Building Node.js metrics app..."
    docker build -t your-repo/nodejs-metrics-app:latest ./apps/nodejs-metrics-app
    
    print_success "All images built successfully"
}

# Function to deploy monitoring stack
deploy_monitoring() {
    print_status "Deploying monitoring stack..."
    
    # Create namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy monitoring components
    kubectl apply -f manifests/monitoring/rbac.yaml
    kubectl apply -f manifests/monitoring/prometheus-config.yaml
    kubectl apply -f manifests/monitoring/prometheus-rules.yaml
    kubectl apply -f manifests/monitoring/prometheus-deployment.yaml
    kubectl apply -f manifests/monitoring/alertmanager-config.yaml
    kubectl apply -f manifests/monitoring/alertmanager-deployment.yaml
    kubectl apply -f manifests/monitoring/grafana-config.yaml
    kubectl apply -f manifests/monitoring/grafana-deployment.yaml
    
    print_success "Monitoring stack deployed"
}

# Function to deploy applications
deploy_applications() {
    print_status "Deploying sample applications..."
    
    kubectl apply -f manifests/apps/nodejs-app/deployment.yaml
    
    print_success "Sample applications deployed"
}

# Function to deploy operator
deploy_operator() {
    print_status "Deploying self-healing operator..."
    
    kubectl apply -f manifests/operator/rbac.yaml
    kubectl apply -f manifests/operator/deployment.yaml
    
    print_success "Self-healing operator deployed"
}

# Function to wait for deployments
wait_for_deployments() {
    print_status "Waiting for all deployments to be ready..."
    
    # Wait for monitoring components
    print_status "Waiting for Prometheus..."
    kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
    
    print_status "Waiting for Alertmanager..."
    kubectl wait --for=condition=ready pod -l app=alertmanager -n monitoring --timeout=300s
    
    print_status "Waiting for Grafana..."
    kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
    
    # Wait for applications
    print_status "Waiting for Node.js app..."
    kubectl wait --for=condition=ready pod -l app=nodejs-app --timeout=300s
    
    # Wait for operator
    print_status "Waiting for self-healing operator..."
    kubectl wait --for=condition=ready pod -l app=self-healing-operator --timeout=300s
    
    print_success "All deployments are ready"
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    echo "=== Pod Status ==="
    kubectl get pods -A
    
    echo -e "\n=== Service Status ==="
    kubectl get svc -A
    
    echo -e "\n=== Checking Prometheus targets ==="
    kubectl port-forward svc/prometheus 9090:9090 -n monitoring &
    PROMETHEUS_PID=$!
    sleep 5
    
    # Check if targets are up
    TARGETS=$(curl -s "http://localhost:9090/api/v1/targets" | jq -r '.data.activeTargets[] | select(.health == "up") | .labels.job' | sort | uniq)
    echo "Active Prometheus targets: $TARGETS"
    
    kill $PROMETHEUS_PID 2>/dev/null || true
    
    print_success "Deployment verification completed"
}

# Function to show access information
show_access_info() {
    print_success "Self-healing infrastructure deployed successfully!"
    echo ""
    echo "=== Access Information ==="
    echo "Grafana:     http://localhost:3000 (admin/admin)"
    echo "Prometheus:  http://localhost:9090"
    echo "Alertmanager: http://localhost:9093"
    echo "Node.js App: http://localhost:8080"
    echo ""
    echo "=== Port Forwarding Commands ==="
    echo "kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    echo "kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
    echo "kubectl port-forward svc/alertmanager 9093:9093 -n monitoring"
    echo "kubectl port-forward svc/nodejs-app 8080:3000"
    echo ""
    echo "=== Testing Commands ==="
    echo "./scripts/simulate-failure.sh memory    # Test memory leak recovery"
    echo "./scripts/simulate-failure.sh crash     # Test pod crash recovery"
    echo "./scripts/simulate-failure.sh errors    # Test error rate recovery"
    echo ""
    echo "=== Monitoring Commands ==="
    echo "kubectl logs -f -l app=self-healing-operator  # Watch operator logs"
    echo "kubectl logs -f -l app=nodejs-app             # Watch app logs"
}

# Function to show help
show_help() {
    echo "Self-Healing Infrastructure Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build-images     Build Docker images before deployment"
    echo "  --skip-monitoring  Skip monitoring stack deployment"
    echo "  --skip-apps        Skip sample applications deployment"
    echo "  --skip-operator    Skip operator deployment"
    echo "  --verify           Verify deployment after completion"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Deploy everything"
    echo "  $0 --build-images     # Build images and deploy everything"
    echo "  $0 --verify           # Deploy and verify"
}

# Main deployment function
main() {
    local BUILD_IMAGES=false
    local SKIP_MONITORING=false
    local SKIP_APPS=false
    local SKIP_OPERATOR=false
    local VERIFY=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-images)
                BUILD_IMAGES=true
                shift
                ;;
            --skip-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            --skip-apps)
                SKIP_APPS=true
                shift
                ;;
            --skip-operator)
                SKIP_OPERATOR=true
                shift
                ;;
            --verify)
                VERIFY=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_status "Starting self-healing infrastructure deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Build images if requested
    if [ "$BUILD_IMAGES" = true ]; then
        build_images
    fi
    
    # Deploy components
    if [ "$SKIP_MONITORING" = false ]; then
        deploy_monitoring
    fi
    
    if [ "$SKIP_APPS" = false ]; then
        deploy_applications
    fi
    
    if [ "$SKIP_OPERATOR" = false ]; then
        deploy_operator
    fi
    
    # Wait for deployments
    wait_for_deployments
    
    # Verify if requested
    if [ "$VERIFY" = true ]; then
        verify_deployment
    fi
    
    # Show access information
    show_access_info
}

# Run main function with all arguments
main "$@" 