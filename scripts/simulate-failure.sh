#!/bin/bash

# Self-Healing Infrastructure Failure Simulation Script
# This script simulates various failure scenarios to test the self-healing system

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

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if the nodejs-app is running
check_app_running() {
    if ! kubectl get pods -l app=nodejs-app --field-selector=status.phase=Running | grep -q nodejs-app; then
        print_error "nodejs-app is not running. Please deploy it first."
        exit 1
    fi
}

# Function to get a random pod name
get_random_pod() {
    kubectl get pods -l app=nodejs-app --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}'
}

# Function to simulate high memory usage
simulate_memory_leak() {
    print_status "Simulating memory leak..."
    
    POD_NAME=$(get_random_pod)
    if [ -z "$POD_NAME" ]; then
        print_error "No running pods found"
        return 1
    fi
    
    print_status "Triggering memory leak in pod: $POD_NAME"
    
    # Send request to trigger memory leak
    kubectl exec -it "$POD_NAME" -- curl -X POST http://localhost:3000/simulate/memory-leak
    
    print_success "Memory leak simulation started. Monitor memory usage in Grafana or Prometheus."
    print_warning "This will trigger the HighMemoryUsage alert after ~1 minute."
}

# Function to simulate pod crash
simulate_pod_crash() {
    print_status "Simulating pod crash..."
    
    POD_NAME=$(get_random_pod)
    if [ -z "$POD_NAME" ]; then
        print_error "No running pods found"
        return 1
    fi
    
    print_status "Triggering crash in pod: $POD_NAME"
    
    # Send request to trigger crash
    kubectl exec -it "$POD_NAME" -- curl -X POST http://localhost:3000/simulate/crash
    
    print_success "Crash simulation triggered. Pod should restart automatically."
    print_warning "This will trigger the PodCrashLooping alert if it happens multiple times."
}

# Function to simulate high error rate
simulate_high_errors() {
    print_status "Simulating high error rate..."
    
    POD_NAME=$(get_random_pod)
    if [ -z "$POD_NAME" ]; then
        print_error "No running pods found"
        return 1
    fi
    
    print_status "Triggering error simulation in pod: $POD_NAME"
    
    # Send request to trigger error simulation
    kubectl exec -it "$POD_NAME" -- curl -X POST http://localhost:3000/simulate/errors
    
    # Generate some traffic to trigger errors
    print_status "Generating traffic to trigger errors..."
    for i in {1..50}; do
        kubectl exec -it "$POD_NAME" -- curl -s http://localhost:3000/api/data > /dev/null &
    done
    wait
    
    print_success "Error simulation started. Monitor error rate in Grafana or Prometheus."
    print_warning "This will trigger the HighErrorRate alert if error rate exceeds 10%."
}

# Function to simulate high CPU usage
simulate_high_cpu() {
    print_status "Simulating high CPU usage..."
    
    POD_NAME=$(get_random_pod)
    if [ -z "$POD_NAME" ]; then
        print_error "No running pods found"
        return 1
    fi
    
    print_status "Generating CPU load in pod: $POD_NAME"
    
    # Create a CPU-intensive task
    kubectl exec -it "$POD_NAME" -- bash -c "
        for i in {1..10}; do
            dd if=/dev/zero bs=1M count=100 | tail &
        done
    " &
    
    print_success "CPU load simulation started. Monitor CPU usage in Grafana or Prometheus."
    print_warning "This will trigger the HighCPUUsage alert if CPU usage exceeds 80%."
}

# Function to stop all simulations
stop_simulations() {
    print_status "Stopping all simulations..."
    
    POD_NAME=$(get_random_pod)
    if [ -z "$POD_NAME" ]; then
        print_error "No running pods found"
        return 1
    fi
    
    kubectl exec -it "$POD_NAME" -- curl -X POST http://localhost:3000/simulate/stop
    
    print_success "All simulations stopped."
}

# Function to check system status
check_status() {
    print_status "Checking system status..."
    
    echo "=== Pod Status ==="
    kubectl get pods -l app=nodejs-app
    
    echo -e "\n=== Service Status ==="
    kubectl get svc -l app=nodejs-app
    
    echo -e "\n=== Operator Status ==="
    kubectl get pods -l app=self-healing-operator
    
    echo -e "\n=== Monitoring Status ==="
    kubectl get pods -n monitoring
}

# Function to show logs
show_logs() {
    print_status "Showing recent logs..."
    
    echo "=== Node.js App Logs ==="
    POD_NAME=$(get_random_pod)
    if [ -n "$POD_NAME" ]; then
        kubectl logs --tail=20 "$POD_NAME"
    fi
    
    echo -e "\n=== Self-Healing Operator Logs ==="
    kubectl logs --tail=20 -l app=self-healing-operator
}

# Function to show help
show_help() {
    echo "Self-Healing Infrastructure Failure Simulation Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  memory     - Simulate memory leak"
    echo "  crash      - Simulate pod crash"
    echo "  errors     - Simulate high error rate"
    echo "  cpu        - Simulate high CPU usage"
    echo "  stop       - Stop all simulations"
    echo "  status     - Check system status"
    echo "  logs       - Show recent logs"
    echo "  help       - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 memory    # Trigger memory leak simulation"
    echo "  $0 crash     # Trigger pod crash simulation"
    echo "  $0 status    # Check current system status"
}

# Main script logic
main() {
    check_kubectl
    check_app_running
    
    case "${1:-help}" in
        memory)
            simulate_memory_leak
            ;;
        crash)
            simulate_pod_crash
            ;;
        errors)
            simulate_high_errors
            ;;
        cpu)
            simulate_high_cpu
            ;;
        stop)
            stop_simulations
            ;;
        status)
            check_status
            ;;
        logs)
            show_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"