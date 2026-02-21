#!/bin/bash

# Self-Healing Infrastructure - Deploy Script
# Usage: ./scripts/deploy.sh

set -e

echo "=== Self-Healing Infrastructure Deployment ==="

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  echo "[ERROR] kubectl not found. Please install kubectl first."
  exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
  echo "[ERROR] Cannot connect to Kubernetes cluster. Check your kubeconfig."
  exit 1
fi

echo "[INFO] Deploying monitoring stack (Prometheus + Alertmanager + Grafana)..."
kubectl apply -f manifests/monitoring/namespace.yaml
kubectl apply -f manifests/monitoring/rbac.yaml
kubectl apply -f manifests/monitoring/prometheus-config.yaml
kubectl apply -f manifests/monitoring/prometheus-rules.yaml
kubectl apply -f manifests/monitoring/prometheus-deployment.yaml
kubectl apply -f manifests/monitoring/alertmanager-config.yaml
kubectl apply -f manifests/monitoring/alertmanager-deployment.yaml
kubectl apply -f manifests/monitoring/grafana-config.yaml
kubectl apply -f manifests/monitoring/grafana-deployment.yaml

echo "[INFO] Deploying Node.js application..."
kubectl apply -f manifests/apps/nodejs-app/deployment.yaml

echo "[INFO] Deploying self-healing operator..."
kubectl apply -f manifests/operator/rbac.yaml
kubectl apply -f manifests/operator/deployment.yaml

echo "[INFO] Waiting for pods to be ready (timeout: 5 minutes)..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=alertmanager -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=nodejs-app --timeout=300s
kubectl wait --for=condition=ready pod -l app=self-healing-operator --timeout=300s

echo ""
echo "=== Deployment Complete! ==="
echo ""
echo "Access the services using port-forward:"
echo "  kubectl port-forward svc/grafana 3000:3000 -n monitoring     # Grafana (admin/admin)"
echo "  kubectl port-forward svc/prometheus 9090:9090 -n monitoring  # Prometheus"
echo "  kubectl port-forward svc/alertmanager 9093:9093 -n monitoring # Alertmanager"
echo "  kubectl port-forward svc/nodejs-app 8080:3000                # Node.js App"
echo ""
echo "Test the self-healing:"
echo "  ./scripts/simulate-failure.sh memory    # Simulate memory leak"
echo "  ./scripts/simulate-failure.sh crash     # Simulate pod crash"
echo "  ./scripts/simulate-failure.sh errors    # Simulate high error rate"
echo "  ./scripts/simulate-failure.sh status    # Check current status"