#!/bin/bash

# Self-Healing Infrastructure - Failure Simulation Script
# Usage: ./scripts/simulate-failure.sh [memory|crash|errors|stop|status|logs]

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  echo "[ERROR] kubectl not found."
  exit 1
fi

# Get the first running nodejs-app pod
get_pod() {
  kubectl get pods -l app=nodejs-app --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

simulate_memory_leak() {
  echo "[INFO] Simulating memory leak..."
  POD=$(get_pod)
  if [ -z "$POD" ]; then
    echo "[ERROR] No running nodejs-app pod found. Is it deployed?"
    exit 1
  fi
  echo "[INFO] Triggering memory leak in pod: $POD"
  kubectl exec "$POD" -- curl -s -X POST http://localhost:3000/simulate/memory-leak
  echo ""
  echo "[INFO] Memory leak started. The HighMemoryUsage alert should fire in ~1 minute."
  echo "[INFO] Watch: kubectl logs -f $POD"
}

simulate_pod_crash() {
  echo "[INFO] Simulating pod crash..."
  POD=$(get_pod)
  if [ -z "$POD" ]; then
    echo "[ERROR] No running nodejs-app pod found. Is it deployed?"
    exit 1
  fi
  echo "[INFO] Triggering crash in pod: $POD"
  kubectl exec "$POD" -- curl -s -X POST http://localhost:3000/simulate/crash || true
  echo "[INFO] Crash triggered. Kubernetes will restart the pod automatically."
  echo "[INFO] Watch: kubectl get pods -l app=nodejs-app -w"
}

simulate_high_errors() {
  echo "[INFO] Simulating high error rate..."
  POD=$(get_pod)
  if [ -z "$POD" ]; then
    echo "[ERROR] No running nodejs-app pod found. Is it deployed?"
    exit 1
  fi
  echo "[INFO] Enabling error simulation in pod: $POD"
  kubectl exec "$POD" -- curl -s -X POST http://localhost:3000/simulate/errors
  echo ""
  echo "[INFO] Generating traffic to trigger errors..."
  for i in $(seq 1 20); do
    kubectl exec "$POD" -- curl -s http://localhost:3000/api/data > /dev/null &
  done
  wait
  echo "[INFO] Error simulation running. The HighErrorRate alert should fire in ~1 minute."
}

stop_simulations() {
  echo "[INFO] Stopping all simulations..."
  POD=$(get_pod)
  if [ -z "$POD" ]; then
    echo "[ERROR] No running nodejs-app pod found."
    exit 1
  fi
  kubectl exec "$POD" -- curl -s -X POST http://localhost:3000/simulate/stop
  echo ""
  echo "[INFO] All simulations stopped."
}

check_status() {
  echo "=== Pod Status ==="
  kubectl get pods -l app=nodejs-app
  echo ""
  echo "=== Operator Status ==="
  kubectl get pods -l app=self-healing-operator
  echo ""
  echo "=== Monitoring Status ==="
  kubectl get pods -n monitoring
}

show_logs() {
  echo "=== Node.js App Logs (last 20 lines) ==="
  POD=$(get_pod)
  if [ -n "$POD" ]; then
    kubectl logs --tail=20 "$POD"
  else
    echo "[WARN] No running nodejs-app pod."
  fi
  echo ""
  echo "=== Self-Healing Operator Logs (last 20 lines) ==="
  kubectl logs --tail=20 -l app=self-healing-operator 2>/dev/null || echo "[WARN] Operator not running."
}

show_help() {
  echo "Self-Healing Infrastructure - Failure Simulation"
  echo ""
  echo "Usage: $0 [COMMAND]"
  echo ""
  echo "Commands:"
  echo "  memory   Simulate memory leak (triggers HighMemoryUsage alert)"
  echo "  crash    Simulate pod crash (triggers PodCrashLooping alert)"
  echo "  errors   Simulate high error rate (triggers HighErrorRate alert)"
  echo "  stop     Stop all running simulations"
  echo "  status   Show current pod/operator status"
  echo "  logs     Show recent logs from app and operator"
}

case "${1:-help}" in
  memory)  simulate_memory_leak ;;
  crash)   simulate_pod_crash ;;
  errors)  simulate_high_errors ;;
  stop)    stop_simulations ;;
  status)  check_status ;;
  logs)    show_logs ;;
  help|--help|-h) show_help ;;
  *)
    echo "[ERROR] Unknown command: $1"
    show_help
    exit 1
    ;;
esac