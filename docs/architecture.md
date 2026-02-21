# Architecture

## Flow

```
Node.js App  →  Prometheus  →  Alertmanager  →  Self-Healing Operator
  /metrics       (scrape)       (webhook)         (restart/redeploy/scale)
```

## Components

| Component | What it does |
|-----------|-------------|
| **nodejs-metrics-app** | Sample Express app that exposes `/metrics`, `/health`, and `/simulate/*` endpoints |
| **Prometheus** | Scrapes metrics, evaluates alert rules every 15s |
| **Alertmanager** | Receives fired alerts from Prometheus, sends webhook to operator |
| **Self-Healing Operator** | Go HTTP server that receives webhook, calls Kubernetes API to recover |

## Alert → Recovery mapping

| Alert | Condition | Recovery |
|-------|-----------|----------|
| HighMemoryUsage | heap memory > 200MB for 1m | delete pod (K8s recreates it) |
| HealthCheckFailed | /metrics unreachable for 1m | delete pod |
| HighErrorRate | >0.1 req/s 5xx for 1m | delete pod |
| HighCPUUsage | >80% CPU for 2m | scale deployment +1 replica |

## Namespaces

- `monitoring` — Prometheus, Alertmanager, Grafana
- `default` — Node.js app, Self-Healing Operator