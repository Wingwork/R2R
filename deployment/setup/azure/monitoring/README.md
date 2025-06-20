# R2R Monitoring Setup with Prometheus and Grafana

This guide covers setting up comprehensive monitoring for the R2R application on Azure Kubernetes Service using Prometheus, Grafana, and AlertManager.

## 📊 Overview

The monitoring stack includes:
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **Node Exporter**: Host metrics
- **kube-state-metrics**: Kubernetes cluster metrics
- **Blackbox Exporter**: External endpoint monitoring

## 📋 Prerequisites

1. **AKS cluster** running with R2R application deployed
2. **Helm 3.x** installed and configured
3. **kubectl** configured to access your cluster
4. **Ingress Controller** deployed (NGINX recommended)
5. **cert-manager** for SSL certificates (optional but recommended)

## 🚀 Quick Start

### 1. Create Monitoring Namespace
```bash
kubectl create namespace monitoring
```

### 2. Add Helm Repositories
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 3. Install Prometheus Stack
```bash
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml \
  --wait
```

### 4. Access Dashboards
```bash
# Grafana (admin/prom-operator)
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring

# Prometheus UI
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# AlertManager UI
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring
```

## 📁 Directory Structure

```
monitoring/
├── README.md                    # This file
├── prometheus-values.yaml      # Prometheus stack configuration
├── grafana-values.yaml         # Grafana-specific configuration
├── alertmanager-config.yaml    # AlertManager configuration
├── dashboards/                 # Custom Grafana dashboards
│   ├── r2r-overview.json
│   ├── r2r-performance.json
│   ├── kubernetes-cluster.json
│   └── azure-metrics.json
├── alerts/                     # Custom alert rules
│   ├── r2r-alerts.yaml
│   ├── kubernetes-alerts.yaml
│   └── infrastructure-alerts.yaml
└── scripts/                    # Utility scripts
    ├── backup-dashboards.sh
    └── restore-dashboards.sh
```

## ⚙️ Configuration

### Prometheus Configuration

The Prometheus stack is configured via `prometheus-values.yaml`:

#### Key Features:
- **High Availability**: 2 replicas with anti-affinity
- **Persistent Storage**: 50GB for metrics retention
- **Service Discovery**: Automatic discovery of services
- **Resource Limits**: Optimized for production workloads
- **Security**: Network policies and RBAC

#### Retention Policy:
- **Metrics Retention**: 30 days
- **Storage Size**: 50GB (automatically expandable)
- **Backup**: Daily snapshots to Azure Storage

### Grafana Configuration

Grafana is configured with:
- **Admin Password**: Auto-generated (retrieve with provided command)
- **Persistent Dashboards**: Stored in ConfigMaps
- **Data Sources**: Pre-configured Prometheus connection
- **Plugins**: Essential monitoring plugins installed
- **Security**: SSL termination and authentication

### AlertManager Configuration

AlertManager handles:
- **Slack Integration**: Critical alerts to Slack channels
- **Email Notifications**: Warning and info alerts via email
- **PagerDuty Integration**: Critical production alerts
- **Alert Routing**: Based on severity and service
- **Silencing**: Maintenance window support

## 📈 Monitoring Metrics

### R2R Application Metrics

#### API Metrics:
- Request rate and latency
- Error rates by endpoint
- Response time percentiles
- Concurrent user sessions
- Authentication success/failure rates

#### LLM Integration Metrics:
- OpenAI/Anthropic API call rates
- Token usage and costs
- Model response times
- API quota utilization
- Error rates by provider

#### Database Metrics:
- PostgreSQL connection pool usage
- Query execution times
- Database size and growth
- Slow query detection
- Vector database performance

#### Workflow Metrics:
- Hatchet workflow execution times
- Task queue depths
- Worker utilization
- Failed workflow rates
- Processing throughput

### Infrastructure Metrics

#### Kubernetes Cluster:
- Node resource utilization (CPU, memory, disk)
- Pod restart rates and failure reasons
- Persistent volume usage
- Network traffic and latency
- DNS resolution times

#### Azure Metrics:
- AKS cluster health and auto-scaling
- Load balancer performance
- Storage account usage
- Key Vault access patterns
- Container registry pull rates

## 🚨 Alerting Rules

### Critical Alerts (PagerDuty + Slack)
```yaml
# High error rate
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
  for: 5m
  
# Database down
- alert: PostgreSQLDown
  expr: up{job="postgresql"} == 0
  for: 1m
  
# Pod crash looping
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
  for: 5m
```

### Warning Alerts (Slack + Email)
```yaml
# High CPU usage
- alert: HighCPUUsage
  expr: rate(cpu_usage_total[5m]) > 0.8
  for: 10m
  
# Disk space low
- alert: DiskSpaceLow
  expr: disk_free_percent < 20
  for: 5m
```

### Info Alerts (Email only)
```yaml
# Certificate expiry
- alert: CertificateExpiringSoon
  expr: cert_expiry_days < 30
  for: 1h
  
# High memory usage
- alert: HighMemoryUsage
  expr: memory_usage_percent > 75
  for: 15m
```

## 📊 Custom Dashboards

### R2R Overview Dashboard
- Application health summary
- Key performance indicators
- Error rate trends
- User activity metrics
- Resource utilization overview

### R2R Performance Dashboard
- API response time analysis
- Database query performance
- LLM integration performance
- Workflow execution metrics
- Cache hit/miss ratios

### Kubernetes Cluster Dashboard
- Node health and capacity
- Pod resource usage
- Network traffic analysis
- Storage utilization
- Cluster events timeline

### Azure Infrastructure Dashboard
- AKS cluster metrics
- Load balancer performance
- Storage account usage
- Cost analysis and optimization
- Security and compliance metrics

## 🔧 Installation Steps

### Step 1: Install Prometheus Stack
```bash
# Install the complete monitoring stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values prometheus-values.yaml \
  --timeout 10m \
  --wait

# Verify installation
kubectl get pods -n monitoring
kubectl get services -n monitoring
```

### Step 2: Configure AlertManager
```bash
# Apply custom AlertManager configuration
kubectl apply -f alertmanager-config.yaml

# Restart AlertManager to pick up new config
kubectl rollout restart statefulset/alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring
```

### Step 3: Import Custom Dashboards
```bash
# Import R2R dashboards
kubectl apply -f dashboards/

# Or import via Grafana UI
# 1. Open Grafana (http://localhost:3000 after port-forward)
# 2. Go to Dashboards -> Import
# 3. Upload JSON files from dashboards/ directory
```

### Step 4: Configure Alerts
```bash
# Apply custom alert rules
kubectl apply -f alerts/

# Verify alerts are loaded
kubectl get prometheusrules -n monitoring
```

### Step 5: Set Up External Access
```bash
# Apply ingress for monitoring services
kubectl apply -f ../kubernetes/ingress.yaml

# Verify external access
curl -k https://r2r.wingwork.com/grafana
curl -k https://r2r.wingwork.com/prometheus
```

## 🔐 Security Configuration

### Authentication
- **Grafana**: Admin user with secure password
- **Prometheus**: Basic auth via NGINX ingress
- **AlertManager**: Basic auth via NGINX ingress

### Network Security
- **Network Policies**: Restrict pod-to-pod communication
- **Ingress Rules**: Controlled external access
- **Service Mesh**: Optional Istio integration

### Data Privacy
- **Metric Sanitization**: Remove sensitive data from metrics
- **Access Control**: Role-based dashboard access
- **Audit Logging**: Track dashboard and query access

## 📧 Alert Configuration

### Slack Integration
```yaml
# Slack webhook configuration
slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
channel: '#r2r-alerts'
username: 'AlertManager'
title: 'R2R Production Alert'
```

### Email Configuration
```yaml
# SMTP configuration
smtp_smarthost: 'smtp.gmail.com:587'
smtp_from: 'alerts@yourcompany.com'
smtp_auth_username: 'alerts@yourcompany.com'
smtp_auth_password: 'your-app-password'
```

### PagerDuty Integration
```yaml
# PagerDuty integration
pagerduty_api_key: 'your-pagerduty-api-key'
service_key: 'your-service-key'
severity: 'critical'
```

## 🛠️ Useful Commands

### Prometheus Queries
```bash
# R2R API request rate
rate(http_requests_total{job="r2r"}[5m])

# Database connection count
pg_stat_database_numbackends{datname="r2r_db"}

# Pod CPU usage
rate(cpu_usage_total{pod=~"r2r-.*"}[5m])

# Memory usage by pod
memory_usage_bytes{pod=~"r2r-.*"}
```

### Grafana Operations
```bash
# Get Grafana admin password
kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode

# Backup dashboards
kubectl get configmaps -n monitoring -l grafana_dashboard=1 -o yaml > dashboards-backup.yaml

# Import dashboard from JSON
curl -X POST \
  http://admin:password@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @dashboard.json
```

### AlertManager Operations
```bash
# Check AlertManager status
kubectl exec -it alertmanager-prometheus-kube-prometheus-alertmanager-0 -n monitoring -- amtool status

# List active alerts
kubectl exec -it alertmanager-prometheus-kube-prometheus-alertmanager-0 -n monitoring -- amtool alert

# Silence alert
kubectl exec -it alertmanager-prometheus-kube-prometheus-alertmanager-0 -n monitoring -- amtool silence add alertname="HighCPUUsage"
```

## 🔄 Maintenance

### Regular Tasks

#### Daily:
- Review alert summary
- Check dashboard functionality
- Verify data collection
- Monitor storage usage

#### Weekly:
- Review and tune alert thresholds
- Update custom dashboards
- Check metric retention
- Analyze performance trends

#### Monthly:
- Update monitoring stack
- Review and clean up old alerts
- Optimize storage and retention
- Security review of access logs

### Backup and Recovery

#### Backup Procedure:
```bash
# Backup Grafana dashboards
./scripts/backup-dashboards.sh

# Backup Prometheus data
kubectl exec -it prometheus-prometheus-kube-prometheus-prometheus-0 -n monitoring -- \
  tar -czf /tmp/prometheus-backup.tar.gz /prometheus/

# Copy backup to local
kubectl cp monitoring/prometheus-prometheus-kube-prometheus-prometheus-0:/tmp/prometheus-backup.tar.gz ./prometheus-backup.tar.gz
```

#### Recovery Procedure:
```bash
# Restore Grafana dashboards
./scripts/restore-dashboards.sh

# Restore Prometheus data (requires pod restart)
kubectl cp ./prometheus-backup.tar.gz monitoring/prometheus-prometheus-kube-prometheus-prometheus-0:/tmp/
kubectl exec -it prometheus-prometheus-kube-prometheus-prometheus-0 -n monitoring -- \
  tar -xzf /tmp/prometheus-backup.tar.gz -C /
```

## 🚨 Troubleshooting

### Common Issues

#### Prometheus Not Scraping Targets
```bash
# Check service discovery
kubectl get servicemonitors -n monitoring
kubectl describe servicemonitor prometheus-kube-prometheus-prometheus -n monitoring

# Check target endpoints
# Go to Prometheus UI -> Status -> Targets
```

#### Grafana Dashboards Not Loading
```bash
# Check Grafana logs
kubectl logs -f deployment/prometheus-grafana -n monitoring

# Verify data source connection
# Go to Grafana UI -> Configuration -> Data Sources
```

#### Alerts Not Firing
```bash
# Check alert rules
kubectl get prometheusrules -n monitoring
kubectl describe prometheusrule r2r-alerts -n monitoring

# Check AlertManager config
kubectl logs -f statefulset/alertmanager-prometheus-kube-prometheus-alertmanager -n monitoring
```

### Performance Optimization

#### High Memory Usage:
- Reduce metric retention period
- Increase resource limits
- Optimize query efficiency
- Add more Prometheus replicas

#### Slow Dashboard Loading:
- Optimize Grafana queries
- Increase Grafana resources
- Use query caching
- Reduce dashboard refresh rates

## 📚 Additional Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kubernetes Monitoring Best Practices](https://kubernetes.io/docs/concepts/cluster-administration/monitoring/)
- [AlertManager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

## 🆘 Support

For monitoring issues:
1. Check pod logs in monitoring namespace
2. Verify service discovery and targets
3. Review dashboard and alert configurations
4. Consult troubleshooting section above
5. Check Azure Monitor for infrastructure issues

---

**Next Step**: After monitoring setup, proceed to [Cloudflare DNS Configuration](../docs/cloudflare-dns.md)