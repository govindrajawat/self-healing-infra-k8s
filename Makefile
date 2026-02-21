# Self-Healing Kubernetes Infrastructure - Makefile
# Variables - set DOCKER_REGISTRY to your Docker Hub or registry username
DOCKER_REGISTRY ?= your-repo
OPERATOR_IMAGE  ?= $(DOCKER_REGISTRY)/self-healing-operator:latest
NODEJS_IMAGE    ?= $(DOCKER_REGISTRY)/nodejs-metrics-app:latest

.PHONY: help build build-operator build-app deploy deploy-monitoring deploy-apps deploy-operator \
        clean status logs port-forward simulate-memory simulate-crash simulate-errors stop-simulations

help: ## Show available commands
	@echo "Self-Healing Kubernetes Infrastructure"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-25s %s\n", $$1, $$2}'

# --- Build ---

build-operator: ## Build the operator Docker image
	docker build -t $(OPERATOR_IMAGE) ./operator

build-app: ## Build the Node.js app Docker image
	docker build -t $(NODEJS_IMAGE) ./apps/nodejs-metrics-app

build: build-operator build-app ## Build all Docker images

# --- Deploy ---

deploy-monitoring: ## Deploy Prometheus, Alertmanager, and Grafana
	kubectl apply -f manifests/monitoring/namespace.yaml
	kubectl apply -f manifests/monitoring/rbac.yaml
	kubectl apply -f manifests/monitoring/prometheus-config.yaml
	kubectl apply -f manifests/monitoring/prometheus-rules.yaml
	kubectl apply -f manifests/monitoring/prometheus-deployment.yaml
	kubectl apply -f manifests/monitoring/alertmanager-config.yaml
	kubectl apply -f manifests/monitoring/alertmanager-deployment.yaml
	kubectl apply -f manifests/monitoring/grafana-config.yaml
	kubectl apply -f manifests/monitoring/grafana-deployment.yaml
	kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
	kubectl wait --for=condition=ready pod -l app=alertmanager -n monitoring --timeout=300s
	kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s

deploy-apps: ## Deploy the Node.js sample application
	kubectl apply -f manifests/apps/nodejs-app/deployment.yaml
	kubectl wait --for=condition=ready pod -l app=nodejs-app --timeout=300s

deploy-operator: ## Deploy the self-healing operator
	kubectl apply -f manifests/operator/rbac.yaml
	kubectl apply -f manifests/operator/deployment.yaml
	kubectl wait --for=condition=ready pod -l app=self-healing-operator --timeout=300s

deploy: deploy-monitoring deploy-apps deploy-operator ## Deploy everything

# --- Cleanup ---

clean: ## Remove all deployed resources
	kubectl delete -f manifests/operator/deployment.yaml --ignore-not-found=true
	kubectl delete -f manifests/operator/rbac.yaml --ignore-not-found=true
	kubectl delete -f manifests/apps/nodejs-app/deployment.yaml --ignore-not-found=true
	kubectl delete namespace monitoring --ignore-not-found=true

# --- Observe ---

status: ## Show status of all pods
	@echo "=== Pods ==="
	kubectl get pods -A
	@echo ""
	@echo "=== Services ==="
	kubectl get svc -A

logs: ## Show recent logs from app and operator
	./scripts/simulate-failure.sh logs

port-forward: ## Print port-forward commands to run in separate terminals
	@echo "Run each of these in a separate terminal:"
	@echo ""
	@echo "  kubectl port-forward svc/grafana 3000:3000 -n monitoring"
	@echo "  kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
	@echo "  kubectl port-forward svc/alertmanager 9093:9093 -n monitoring"
	@echo "  kubectl port-forward svc/nodejs-app 8080:3000"
	@echo ""
	@echo "  Grafana:      http://localhost:3000  (admin/admin)"
	@echo "  Prometheus:   http://localhost:9090"
	@echo "  Alertmanager: http://localhost:9093"
	@echo "  Node.js App:  http://localhost:8080"

# --- Simulate Failures ---

simulate-memory: ## Simulate a memory leak
	./scripts/simulate-failure.sh memory

simulate-crash: ## Simulate a pod crash
	./scripts/simulate-failure.sh crash

simulate-errors: ## Simulate high error rate
	./scripts/simulate-failure.sh errors

stop-simulations: ## Stop all failure simulations
	./scripts/simulate-failure.sh stop