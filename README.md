# Self-Healing Kubernetes Infrastructure 🚀

[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.25+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Prometheus](https://img.shields.io/badge/Prometheus-2.40+-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Go](https://img.shields.io/badge/Go-1.19+-00ADD8?logo=go&logoColor=white)](https://golang.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Automatically detect and recover from failures in Kubernetes using Prometheus alerts and custom recovery logic.

## 🎯 Features

- 🚨 **Smart Alerting**: Monitor pod crashes, high memory usage, and 5xx errors
- 🔄 **Auto-Recovery**: Automatically restart pods or redeploy deployments
- 📊 **Real-time Monitoring**: Grafana dashboards with alert visualizations
- 🎮 **Failure Simulation**: Easy-to-use scripts to test recovery scenarios
- 🔧 **Custom Operator**: Go-based webhook receiver for intelligent recovery decisions

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Sample App    │    │   Prometheus    │    │ Alertmanager    │
│   (Node.js)     │───▶│   + Rules       │───▶│   + Webhook     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Grafana       │    │   Custom        │    │   Kubernetes    │
│   Dashboards    │    │   Operator      │    │   API Server    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster (minikube, kind, or cloud)
- kubectl configured
- Helm 3.x

### 1. Deploy the Infrastructure

```bash
# Clone the repository
git clone https://github.com/your-username/self-healing-infra-k8s.git
cd self-healing-infra-k8s

# Deploy everything
make deploy

# Or deploy step by step
make deploy-monitoring    # Prometheus + Alertmanager + Grafana
make deploy-apps         # Sample applications
make deploy-operator     # Custom recovery operator
```

### 2. Verify Deployment

```bash
# Check all components are running
kubectl get pods -A

# Access Grafana (default: admin/admin)
kubectl port-forward svc/grafana 3000:80

# Access sample app
kubectl port-forward svc/nodejs-app 8080:3000
```

### 3. Simulate Failures

```bash
# Simulate high memory usage
make simulate-memory

# Simulate pod crash loop
make simulate-crash

# Simulate 5xx errors
make simulate-errors
```

## 📁 Project Structure

```
self-healing-infra-k8s/
├── manifests/                 # Kubernetes manifests
│   ├── apps/                 # Sample applications
│   │   └── nodejs-app/       # Node.js app with metrics
│   ├── monitoring/           # Monitoring stack
│   │   ├── prometheus/       # Prometheus configuration
│   │   ├── alertmanager/     # Alertmanager configuration
│   │   └── grafana/          # Grafana dashboards
│   └── operator/             # RBAC for custom operator
├── operator/                 # Custom recovery operator
│   ├── main.go              # Webhook receiver
│   ├── Dockerfile           # Container image
│   └── kustomization.yaml   # Deployment config
├── apps/                     # Sample application source
│   └── nodejs-metrics-app/   # Node.js app with health endpoints
├── scripts/                  # Utility scripts
│   ├── deploy.sh            # Deployment script
│   └── simulate-failure.sh  # Failure simulation
├── docs/                     # Documentation
│   └── architecture.png     # Architecture diagram
├── Makefile                  # Build and deployment commands
└── README.md                # This file
```

## 🔧 Configuration

### Alert Rules

The system includes pre-configured alert rules in `manifests/monitoring/prometheus-rules.yaml`:

- **HighMemoryUsage**: Triggers when container memory > 200Mi
- **PodCrashLooping**: Triggers when pod restarts > 3 times
- **HighErrorRate**: Triggers when 5xx error rate > 10%

### Recovery Actions

The custom operator supports these recovery actions:

- `restart`: Delete the problematic pod (Kubernetes will recreate it)
- `redeploy`: Trigger a rolling update of the deployment
- `scale`: Scale the deployment up or down

## 🧪 Testing Scenarios

### Scenario 1: High Memory Usage
```bash
make simulate-memory
# Expected: Pod gets restarted automatically
```

### Scenario 2: Pod Crash Loop
```bash
make simulate-crash
# Expected: Deployment gets redeployed
```

### Scenario 3: High Error Rate
```bash
make simulate-errors
# Expected: Pod gets restarted
```

## 📊 Monitoring

### Grafana Dashboards

Access Grafana at `http://localhost:3000` (admin/admin) to view:

- **Self-Healing Overview**: Overall system health and recovery actions
- **Application Metrics**: Memory, CPU, and error rates
- **Alert History**: Timeline of triggered alerts and recoveries

### Prometheus Queries

```promql
# Memory usage by pod
container_memory_usage_bytes{container="nodejs-app"}

# Pod restart count
kube_pod_container_status_restarts_total{container="nodejs-app"}

# HTTP error rate
rate(http_requests_total{status=~"5.."}[5m])
```

## 🔍 Troubleshooting

### Check Operator Logs
```bash
kubectl logs -f deployment/self-healing-operator
```

### Check Alertmanager
```bash
kubectl port-forward svc/alertmanager 9093:9093
# Access at http://localhost:9093
```

### Check Prometheus Rules
```bash
kubectl get prometheusrules -A
kubectl describe prometheusrule self-healing-rules
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts)
- [Kubernetes Client Go](https://github.com/kubernetes/client-go)

---

**Made with ❤️ for resilient Kubernetes infrastructure**