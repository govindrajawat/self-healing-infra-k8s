# Self-Healing Kubernetes Infrastructure

Automatically detect and recover from failures in Kubernetes using Prometheus alerts and a simple Go webhook operator.

## How It Works

```
Node.js App  →  Prometheus  →  Alertmanager  →  Self-Healing Operator
   (metrics)       (rules)        (webhook)          (restart/redeploy)
```

1. The **Node.js app** exposes Prometheus metrics at `/metrics`
2. **Prometheus** evaluates alert rules (high memory, crashes, errors)
3. **Alertmanager** sends a webhook to the operator when an alert fires
4. The **operator** takes a recovery action (restart pod, redeploy, or scale up)

## Prerequisites

- A running Kubernetes cluster (minikube or kind works fine)
- `kubectl` configured to connect to the cluster
- Docker (to build images)

## Quick Start

### 1. Build Docker images

```bash
# Set DOCKER_REGISTRY to your Docker Hub username or registry
make build DOCKER_REGISTRY=myusername
```

### 2. Push images (if using a remote registry)

```bash
docker push myusername/self-healing-operator:latest
docker push myusername/nodejs-metrics-app:latest
```

> If using minikube, you can load images directly:
> ```bash
> minikube image load myusername/self-healing-operator:latest
> minikube image load myusername/nodejs-metrics-app:latest
> ```

### 3. Update image names in manifests

Edit `manifests/apps/nodejs-app/deployment.yaml` and `manifests/operator/deployment.yaml`
and replace `your-repo/...` with your actual image names.

### 4. Deploy everything

```bash
make deploy
```

### 5. Access the services

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring      # http://localhost:3000 (admin/admin)
kubectl port-forward svc/prometheus 9090:9090 -n monitoring   # http://localhost:9090
kubectl port-forward svc/nodejs-app 8080:3000                  # http://localhost:8080
```

## Testing Self-Healing

```bash
# Simulate a memory leak - operator will restart the pod
./scripts/simulate-failure.sh memory

# Simulate a pod crash - Kubernetes restarts it, operator reacts to crash loop
./scripts/simulate-failure.sh crash

# Simulate high error rate - operator will restart the pod
./scripts/simulate-failure.sh errors

# Stop all simulations
./scripts/simulate-failure.sh stop

# Check what's running
./scripts/simulate-failure.sh status
```

## Project Structure

```
self-healing-infra-k8s/
├── apps/nodejs-metrics-app/    # Sample Node.js app with Prometheus metrics
│   ├── app.js                  # Express server with /metrics, /health, /simulate/* endpoints
│   ├── package.json
│   └── Dockerfile
├── operator/                   # Self-healing webhook operator (Go)
│   ├── main.go                 # Receives Alertmanager webhooks, executes recovery
│   ├── go.mod
│   └── Dockerfile
├── manifests/
│   ├── apps/nodejs-app/        # Kubernetes Deployment + Service for the app
│   ├── monitoring/             # Prometheus, Alertmanager, Grafana configs + deployments
│   └── operator/               # RBAC + Deployment for the operator
├── scripts/
│   ├── deploy.sh               # Full deploy script (alternative to make deploy)
│   └── simulate-failure.sh     # Trigger failure scenarios
└── Makefile                    # Convenience commands
```

## Alert Rules

Defined in `manifests/monitoring/prometheus-rules.yaml`:

| Alert | Condition | Recovery Action |
|-------|-----------|-----------------|
| HighMemoryUsage | Container memory > 200Mi for 1m | restart pod |
| PodCrashLooping | >3 restarts in 5 minutes | redeploy deployment |
| HighErrorRate | >10% 5xx errors for 1m | restart pod |
| HighCPUUsage | >80% CPU for 2m | scale up |
| HealthCheckFailed | /health not responding for 1m | restart pod |

## Cleanup

```bash
make clean
```

## Troubleshooting

```bash
# Check operator logs to see what recovery actions are running
kubectl logs -f -l app=self-healing-operator

# Check if Alertmanager is receiving alerts
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
# Then open http://localhost:9093

# Check Prometheus alert rules are loaded
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Then open http://localhost:9090/alerts
```