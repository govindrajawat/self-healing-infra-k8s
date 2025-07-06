# Self-Healing Kubernetes Infrastructure Makefile

# Variables
DOCKER_REGISTRY ?= your-repo
OPERATOR_IMAGE ?= $(DOCKER_REGISTRY)/self-healing-operator:latest
NODEJS_IMAGE ?= $(DOCKER_REGISTRY)/nodejs-metrics-app:latest
KUBECONFIG ?= ~/.kube/config

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

.PHONY: help build deploy deploy-monitoring deploy-apps deploy-operator clean logs status simulate-memory simulate-crash simulate-errors simulate-cpu stop-simulations

# Default target
help: ## Show this help message
	@echo "Self-Healing Kubernetes Infrastructure"
	@echo ""
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Build targets
build-operator: ## Build the custom operator Docker image
	@echo "$(BLUE)Building operator image...$(NC)"
	docker build -t $(OPERATOR_IMAGE) ./operator
	@echo "$(GREEN)Operator image built successfully$(NC)"

build-app: ## Build the Node.js application Docker image
	@echo "$(BLUE)Building Node.js app image...$(NC)"
	docker build -t $(NODEJS_IMAGE) ./apps/nodejs-metrics-app
	@echo "$(GREEN)Node.js app image built successfully$(NC)"

build: build-operator build-app ## Build all Docker images

# Deploy targets
deploy-monitoring: ## Deploy monitoring stack (Prometheus, Alertmanager, Grafana)
	@echo "$(BLUE)Deploying monitoring stack...$(NC)"
	kubectl apply -f manifests/monitoring/namespace.yaml
	kubectl apply -f manifests/monitoring/rbac.yaml
	kubectl apply -f manifests/monitoring/prometheus-config.yaml
	kubectl apply -f manifests/monitoring/prometheus-rules.yaml
	kubectl apply -f manifests/monitoring/prometheus-deployment.yaml
	kubectl apply -f manifests/monitoring/alertmanager-config.yaml
	kubectl apply -f manifests/monitoring/alertmanager-deployment.yaml
	kubectl apply -f manifests/monitoring/grafana-config.yaml
	kubectl apply -f manifests/monitoring/grafana-deployment.yaml
	@echo "$(GREEN)Monitoring stack deployed successfully$(NC)"
	@echo "$(YELLOW)Waiting for monitoring pods to be ready...$(NC)"
	kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
	kubectl wait --for=condition=ready pod -l app=alertmanager -n monitoring --timeout=300s
	kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

deploy-apps: ## Deploy sample applications
	@echo "$(BLUE)Deploying sample applications...$(NC)"
	kubectl apply -f manifests/apps/nodejs-app/deployment.yaml
	@echo "$(GREEN)Sample applications deployed successfully$(NC)"
	@echo "$(YELLOW)Waiting for app pods to be ready...$(NC)"
	kubectl wait --for=condition=ready pod -l app=nodejs-app --timeout=300s

deploy-operator: ## Deploy the custom self-healing operator
	@echo "$(BLUE)Deploying self-healing operator...$(NC)"
	kubectl apply -f manifests/operator/rbac.yaml
	kubectl apply -f manifests/operator/deployment.yaml
	@echo "$(GREEN)Self-healing operator deployed successfully$(NC)"
	@echo "$(YELLOW)Waiting for operator pod to be ready...$(NC)"
	kubectl wait --for=condition=ready pod -l app=self-healing-operator --timeout=300s

deploy: deploy-monitoring deploy-apps deploy-operator ## Deploy everything

# Cleanup targets
clean-monitoring: ## Remove monitoring stack
	@echo "$(BLUE)Removing monitoring stack...$(NC)"
	kubectl delete -f manifests/monitoring/grafana-deployment.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/alertmanager-deployment.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/prometheus-deployment.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/prometheus-rules.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/prometheus-config.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/alertmanager-config.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/grafana-config.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/rbac.yaml --ignore-not-found=true
	kubectl delete -f manifests/monitoring/namespace.yaml --ignore-not-found=true

clean-apps: ## Remove sample applications
	@echo "$(BLUE)Removing sample applications...$(NC)"
	kubectl delete -f manifests/apps/nodejs-app/deployment.yaml --ignore-not-found=true

clean-operator: ## Remove the custom operator
	@echo "$(BLUE)Removing self-healing operator...$(NC)"
	kubectl delete -f manifests/operator/deployment.yaml --ignore-not-found=true
	kubectl delete -f manifests/operator/rbac.yaml --ignore-not-found=true

clean: clean-apps clean-operator clean-monitoring ## Remove everything

# Status and logs
status: ## Show status of all components
	@echo "$(BLUE)=== Pod Status ===$(NC)"
	kubectl get pods -A
	@echo "$(BLUE)=== Service Status ===$(NC)"
	kubectl get svc -A
	@echo "$(BLUE)=== Deployment Status ===$(NC)"
	kubectl get deployments -A

logs-app: ## Show Node.js app logs
	@echo "$(BLUE)Node.js App Logs:$(NC)"
	kubectl logs -l app=nodejs-app --tail=50

logs-operator: ## Show operator logs
	@echo "$(BLUE)Self-Healing Operator Logs:$(NC)"
	kubectl logs -l app=self-healing-operator --tail=50

logs-prometheus: ## Show Prometheus logs
	@echo "$(BLUE)Prometheus Logs:$(NC)"
	kubectl logs -l app=prometheus -n monitoring --tail=50

logs-alertmanager: ## Show Alertmanager logs
	@echo "$(BLUE)Alertmanager Logs:$(NC)"
	kubectl logs -l app=alertmanager -n monitoring --tail=50

logs: logs-app logs-operator logs-prometheus logs-alertmanager ## Show all logs

# Port forwarding
port-forward-grafana: ## Forward Grafana port (admin/admin)
	@echo "$(BLUE)Forwarding Grafana port 3000...$(NC)"
	kubectl port-forward svc/grafana 3000:3000 -n monitoring

port-forward-prometheus: ## Forward Prometheus port
	@echo "$(BLUE)Forwarding Prometheus port 9090...$(NC)"
	kubectl port-forward svc/prometheus 9090:9090 -n monitoring

port-forward-alertmanager: ## Forward Alertmanager port
	@echo "$(BLUE)Forwarding Alertmanager port 9093...$(NC)"
	kubectl port-forward svc/alertmanager 9093:9093 -n monitoring

port-forward-app: ## Forward Node.js app port
	@echo "$(BLUE)Forwarding Node.js app port 8080...$(NC)"
	kubectl port-forward svc/nodejs-app 8080:3000

# Simulation targets
simulate-memory: ## Simulate memory leak
	@echo "$(BLUE)Simulating memory leak...$(NC)"
	./scripts/simulate-failure.sh memory

simulate-crash: ## Simulate pod crash
	@echo "$(BLUE)Simulating pod crash...$(NC)"
	./scripts/simulate-failure.sh crash

simulate-errors: ## Simulate high error rate
	@echo "$(BLUE)Simulating high error rate...$(NC)"
	./scripts/simulate-failure.sh errors

simulate-cpu: ## Simulate high CPU usage
	@echo "$(BLUE)Simulating high CPU usage...$(NC)"
	./scripts/simulate-failure.sh cpu

stop-simulations: ## Stop all simulations
	@echo "$(BLUE)Stopping all simulations...$(NC)"
	./scripts/simulate-failure.sh stop

# Testing targets
test-alerts: ## Test alert rules
	@echo "$(BLUE)Testing alert rules...$(NC)"
	kubectl port-forward svc/prometheus 9090:9090 -n monitoring &
	sleep 5
	curl -s "http://localhost:9090/api/v1/rules" | jq '.data.groups[] | select(.name == "self-healing") | .rules[].name'
	pkill -f "port-forward.*prometheus"

test-webhook: ## Test webhook endpoint
	@echo "$(BLUE)Testing webhook endpoint...$(NC)"
	kubectl port-forward svc/self-healing-operator 8080:8080 &
	sleep 3
	curl -X POST http://localhost:8080/health
	pkill -f "port-forward.*self-healing-operator"

test: test-alerts test-webhook ## Run all tests

# Utility targets
check-prerequisites: ## Check if all prerequisites are installed
	@echo "$(BLUE)Checking prerequisites...$(NC)"
	@command -v kubectl >/dev/null 2>&1 || { echo "$(RED)kubectl is required but not installed$(NC)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)docker is required but not installed$(NC)"; exit 1; }
	@command -v make >/dev/null 2>&1 || { echo "$(RED)make is required but not installed$(NC)"; exit 1; }
	@echo "$(GREEN)All prerequisites are installed$(NC)"

create-namespace: ## Create monitoring namespace
	@echo "$(BLUE)Creating monitoring namespace...$(NC)"
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Quick start
quick-start: check-prerequisites create-namespace build deploy ## Quick start - build and deploy everything
	@echo "$(GREEN)Self-healing infrastructure is ready!$(NC)"
	@echo "$(YELLOW)Access points:$(NC)"
	@echo "  Grafana: http://localhost:3000 (admin/admin)"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Alertmanager: http://localhost:9093"
	@echo "  Node.js App: http://localhost:8080"
	@echo ""
	@echo "$(YELLOW)Use 'make simulate-memory' to test the self-healing system$(NC)" 