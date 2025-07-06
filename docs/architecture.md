# Self-Healing Infrastructure Architecture

## Overview

The self-healing infrastructure is designed to automatically detect and recover from failures in Kubernetes applications using Prometheus monitoring and custom recovery logic.

## Architecture Components

### 1. Sample Application (Node.js)
- **Purpose**: Demonstrates the self-healing capabilities
- **Features**:
  - Exposes Prometheus metrics at `/metrics`
  - Health check endpoint at `/health`
  - Built-in failure simulation endpoints
  - Memory leak, crash, and error simulation capabilities

### 2. Monitoring Stack

#### Prometheus
- **Role**: Metrics collection and alerting
- **Configuration**:
  - Scrapes metrics from Node.js app every 15 seconds
  - Stores metrics for 200 hours
  - Evaluates alert rules every 15 seconds
- **Alerts**: High memory usage, pod crashes, high error rates

#### Alertmanager
- **Role**: Alert routing and notification
- **Configuration**:
  - Routes critical alerts to self-healing webhook
  - Groups alerts by alert name
  - Sends resolved notifications
- **Webhook**: Calls custom operator for recovery actions

#### Grafana
- **Role**: Visualization and dashboards
- **Features**:
  - Pre-configured dashboards for self-healing overview
  - Real-time monitoring of application health
  - Alert history visualization

### 3. Custom Self-Healing Operator

#### Webhook Receiver
- **Endpoint**: `/webhook`
- **Function**: Receives alerts from Alertmanager
- **Processing**:
  - Parses alert payload
  - Extracts recovery action and target information
  - Executes appropriate recovery action

#### Recovery Actions
1. **Pod Restart**: Deletes problematic pod (Kubernetes recreates it)
2. **Deployment Redeploy**: Triggers rolling update
3. **Scale**: Increases replica count

#### RBAC Permissions
- Read/write access to pods
- Read/write access to deployments
- Event creation permissions

## Data Flow

```
1. Application generates metrics
   ↓
2. Prometheus scrapes metrics
   ↓
3. Alert rules evaluate conditions
   ↓
4. Alertmanager receives alerts
   ↓
5. Webhook sends alert to operator
   ↓
6. Operator executes recovery action
   ↓
7. Kubernetes applies recovery
   ↓
8. Application returns to healthy state
```

## Alert Rules

### HighMemoryUsage
- **Trigger**: Container memory > 200MB
- **Duration**: 1 minute
- **Action**: Restart pod
- **Recovery**: Pod deletion triggers recreation

### PodCrashLooping
- **Trigger**: Pod restarts > 3 in 5 minutes
- **Duration**: 2 minutes
- **Action**: Redeploy deployment
- **Recovery**: Rolling update with new annotation

### HighErrorRate
- **Trigger**: 5xx error rate > 10%
- **Duration**: 1 minute
- **Action**: Restart pod
- **Recovery**: Pod deletion triggers recreation

### PodNotReady
- **Trigger**: Pod running but not ready
- **Duration**: 2 minutes
- **Action**: Restart pod
- **Recovery**: Pod deletion triggers recreation

### HighCPUUsage
- **Trigger**: CPU usage > 80%
- **Duration**: 2 minutes
- **Action**: Scale deployment
- **Recovery**: Increase replica count

## Failure Scenarios

### 1. Memory Leak
- **Simulation**: POST `/simulate/memory-leak`
- **Detection**: HighMemoryUsage alert
- **Recovery**: Pod restart
- **Expected Time**: 1-2 minutes

### 2. Pod Crash
- **Simulation**: POST `/simulate/crash`
- **Detection**: PodCrashLooping alert
- **Recovery**: Deployment redeploy
- **Expected Time**: 2-3 minutes

### 3. High Error Rate
- **Simulation**: POST `/simulate/errors`
- **Detection**: HighErrorRate alert
- **Recovery**: Pod restart
- **Expected Time**: 1-2 minutes

### 4. High CPU Usage
- **Simulation**: CPU-intensive tasks
- **Detection**: HighCPUUsage alert
- **Recovery**: Scale deployment
- **Expected Time**: 2-3 minutes

## Monitoring and Observability

### Metrics Exposed
- HTTP request counts and durations
- Memory usage
- CPU usage
- Pod restart counts
- Application-specific metrics

### Dashboards
- **Self-Healing Overview**: Overall system health
- **Application Metrics**: Detailed app performance
- **Alert History**: Timeline of alerts and recoveries

### Logs
- Application logs with structured logging
- Operator logs with recovery actions
- Prometheus and Alertmanager logs

## Security Considerations

### RBAC
- Minimal required permissions for operator
- Namespace-scoped where possible
- Read-only access to monitoring data

### Network Security
- Internal service communication only
- No external ingress by default
- Webhook authentication (can be enhanced)

### Container Security
- Non-root user execution
- Minimal base images
- Resource limits and requests

## Scalability

### Horizontal Scaling
- Multiple operator replicas (with leader election)
- Multiple Prometheus instances
- Multiple Alertmanager instances

### Vertical Scaling
- Resource limits and requests configured
- Auto-scaling based on metrics
- Graceful handling of resource constraints

## Troubleshooting

### Common Issues
1. **Webhook not receiving alerts**: Check Alertmanager configuration
2. **Recovery actions failing**: Check RBAC permissions
3. **Metrics not appearing**: Check Prometheus scrape configuration
4. **Alerts not firing**: Check alert rule expressions

### Debug Commands
```bash
# Check operator logs
kubectl logs -f -l app=self-healing-operator

# Check alert status
kubectl port-forward svc/alertmanager 9093:9093
# Visit http://localhost:9093

# Check Prometheus targets
kubectl port-forward svc/prometheus 9090:9090
# Visit http://localhost:9090/targets

# Test webhook manually
curl -X POST http://localhost:8080/webhook -H "Content-Type: application/json" -d '{"alerts":[...]}'
```

## Future Enhancements

### Advanced Recovery Actions
- Database connection pool resets
- Cache clearing
- Configuration reloading
- Service mesh circuit breaker resets

### Machine Learning
- Anomaly detection for metrics
- Predictive failure detection
- Optimal recovery action selection

### Integration
- Slack/Teams notifications
- PagerDuty integration
- ServiceNow ticket creation
- Custom webhook endpoints

### Observability
- Distributed tracing
- Custom metrics for recovery success rates
- A/B testing of recovery strategies
- Recovery action performance analytics 