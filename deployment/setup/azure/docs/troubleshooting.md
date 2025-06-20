# R2R Azure Deployment Troubleshooting & Maintenance Guide

This comprehensive guide covers troubleshooting common issues and maintaining your R2R deployment on Azure Kubernetes Service.

## 🚨 Quick Diagnostics

### System Health Check
```bash
#!/bin/bash
# health-check.sh - Quick system health verification

echo "=== R2R Azure Deployment Health Check ==="

# Check Terraform infrastructure
echo "🏗️  Infrastructure Status:"
cd deployment/setup/azure/terraform
terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'

# Check Kubernetes cluster connectivity
echo -e "\n🔗 Kubernetes Connectivity:"
kubectl cluster-info --request-timeout=10s

# Check namespace and pods
echo -e "\n📦 Pod Status:"
kubectl get pods -n ai-system -o wide

# Check services and ingress
echo -e "\n🌐 Network Status:"
kubectl get svc,ingress -n ai-system

# Check certificates
echo -e "\n🔒 SSL Certificate Status:"
kubectl get certificates -n ai-system

# Test application endpoints
echo -e "\n🚀 Application Health:"
if curl -s --max-time 10 https://r2r.wingwork.com/v3/health > /dev/null; then
    echo "✅ R2R API is responding"
else
    echo "❌ R2R API is not responding"
fi

# Check monitoring
echo -e "\n📊 Monitoring Status:"
kubectl get pods -n monitoring 2>/dev/null | grep -E "(prometheus|grafana|alertmanager)" || echo "Monitoring not deployed"

echo -e "\n=== Health Check Complete ==="
```

## 🔧 Infrastructure Issues

### Terraform Problems

#### State Issues
```bash
# Refresh Terraform state
terraform refresh

# Import missing resources
terraform import azurerm_kubernetes_cluster.main /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ContainerService/managedClusters/{cluster-name}

# Fix state corruption
terraform state list
terraform state rm azurerm_resource_group.main
terraform import azurerm_resource_group.main /subscriptions/{sub-id}/resourceGroups/{rg-name}
```

#### Authentication Problems
```bash
# Re-authenticate with Azure
az login --use-device-code
az account set --subscription "your-subscription-id"

# Check current context
az account show
az ad signed-in-user show

# Clear cached credentials
az logout
rm -rf ~/.azure
az login
```

#### Resource Quotas
```bash
# Check quota usage
az vm list-usage --location eastus -o table
az network list-usages --location eastus -o table

# Request quota increase
az support tickets create \
  --ticket-name "Increase VM quota" \
  --description "Need more VMs for R2R deployment" \
  --problem-classification "/providers/Microsoft.Support/services/quota-service-guid/problemClassifications/vm-cores-quota-guid"
```

### AKS Cluster Issues

#### Node Problems
```bash
# Check node status
kubectl get nodes -o wide
kubectl describe nodes

# Check node resource usage
kubectl top nodes

# Restart problematic nodes
az aks nodepool scale --name agentpool --cluster-name aks-r2r-prod --resource-group rg-r2r-prod --node-count 0
az aks nodepool scale --name agentpool --cluster-name aks-r2r-prod --resource-group rg-r2r-prod --node-count 3

# Check Azure disk issues
kubectl get events --sort-by=.metadata.creationTimestamp | grep -i "disk\|volume\|mount"
```

#### Networking Issues
```bash
# Check CNI configuration
kubectl get pods -n kube-system | grep -E "(azure-cni|calico)"

# Test pod-to-pod connectivity
kubectl run test-pod --image=busybox --rm -it -- sh
# Inside pod: nslookup kubernetes.default.svc.cluster.local

# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local

# Validate network policies
kubectl get networkpolicies -A
kubectl describe networkpolicy default-deny -n ai-system
```

## 🐛 Application Issues

### Pod Startup Problems

#### ImagePullBackOff
```bash
# Check image pull secrets
kubectl get secrets -n ai-system | grep docker

# Test ACR connectivity
az acr login --name $(terraform output -raw acr_name)
docker pull $(terraform output -raw acr_login_server)/r2r:latest

# Create or update image pull secret
kubectl create secret docker-registry acr-secret \
  --docker-server=$(terraform output -raw acr_login_server) \
  --docker-username=$(az acr credential show --name $(terraform output -raw acr_name) --query username -o tsv) \
  --docker-password=$(az acr credential show --name $(terraform output -raw acr_name) --query passwords[0].value -o tsv) \
  --namespace ai-system
```

#### CrashLoopBackOff
```bash
# Check pod logs
kubectl logs -f deployment/r2r -n ai-system --previous

# Debug pod startup
kubectl describe pod <pod-name> -n ai-system

# Check resource limits
kubectl get pods -n ai-system -o custom-columns=NAME:.metadata.name,REQUESTS:.spec.containers[0].resources.requests,LIMITS:.spec.containers[0].resources.limits

# Temporarily increase resources
kubectl patch deployment r2r -n ai-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"r2r","resources":{"limits":{"memory":"2Gi","cpu":"1000m"},"requests":{"memory":"1Gi","cpu":"500m"}}}]}}}}'
```

#### Pending Pods
```bash
# Check resource availability
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"

# Check pod requirements vs available resources
kubectl describe pod <pending-pod> -n ai-system

# Check persistent volume claims
kubectl get pvc -n ai-system
kubectl describe pvc <pvc-name> -n ai-system

# Force pod rescheduling
kubectl delete pod <pod-name> -n ai-system
```

### Database Issues

#### PostgreSQL Connection Problems
```bash
# Check PostgreSQL pod status
kubectl get pods -n ai-system -l app.kubernetes.io/name=postgresql

# Test database connectivity
kubectl run postgres-client --rm -it --image=postgres:16 --env="PGPASSWORD=yourpassword" --command -- bash
# Inside pod: psql -h postgresql.ai-system.svc.cluster.local -U postgres -d r2r

# Check database logs
kubectl logs -f sts/postgresql -n ai-system

# Reset PostgreSQL password
kubectl patch secret postgresql-secrets -n ai-system -p '{"data":{"postgres-password":"'$(echo -n "newpassword" | base64)'"}}'
kubectl rollout restart statefulset/postgresql -n ai-system
```

#### Database Performance Issues
```bash
# Check database resource usage
kubectl exec -it postgresql-0 -n ai-system -- psql -U postgres -d r2r -c "
SELECT 
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query,
    state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
"

# Check database size
kubectl exec -it postgresql-0 -n ai-system -- psql -U postgres -d r2r -c "
SELECT 
    pg_database.datname,
    pg_database_size(pg_database.datname) AS size
FROM pg_database;
"

# Analyze slow queries
kubectl exec -it postgresql-0 -n ai-system -- psql -U postgres -d r2r -c "
SELECT query, mean_time, calls
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
"
```

### Hatchet Workflow Issues

#### Workflow Engine Problems
```bash
# Check Hatchet components
kubectl get pods -n ai-system -l app.kubernetes.io/name=hatchet

# Check Hatchet logs
kubectl logs -f deployment/hatchet-api -n ai-system
kubectl logs -f deployment/hatchet-engine -n ai-system

# Test Hatchet connectivity
kubectl port-forward svc/hatchet-dashboard 8080:80 -n ai-system
# Visit http://localhost:8080

# Check RabbitMQ status
kubectl exec -it hatchet-rabbitmq-0 -n ai-system -- rabbitmqctl status
kubectl exec -it hatchet-rabbitmq-0 -n ai-system -- rabbitmqctl list_queues
```

#### Task Queue Problems
```bash
# Check queue depths
kubectl exec -it hatchet-rabbitmq-0 -n ai-system -- rabbitmqctl list_queues name messages consumers

# Purge stuck queues (use with caution)
kubectl exec -it hatchet-rabbitmq-0 -n ai-system -- rabbitmqctl purge_queue task_queue

# Restart Hatchet workers
kubectl rollout restart deployment/hatchet-engine -n ai-system
```

## 🌐 Network & DNS Issues

### Ingress Controller Problems

#### NGINX Ingress Issues
```bash
# Check ingress controller status
kubectl get pods -n ingress-nginx
kubectl logs -f deployment/ingress-nginx-controller -n ingress-nginx

# Test ingress configuration
kubectl get ingress -n ai-system -o yaml

# Check backend connectivity
kubectl describe ingress r2r-ingress -n ai-system

# Test service endpoints
kubectl get endpoints -n ai-system
```

#### Load Balancer Issues
```bash
# Check Azure Load Balancer status
az network lb list --resource-group $(terraform output -raw aks_node_resource_group) -o table

# Check public IP assignment
az network public-ip list --resource-group $(terraform output -raw aks_node_resource_group) -o table

# Test load balancer directly
curl -I http://$(terraform output -raw public_ip_address)

# Check load balancer backend health
az network lb probe list --lb-name kubernetes --resource-group $(terraform output -raw aks_node_resource_group) -o table
```

### SSL Certificate Issues

#### cert-manager Problems
```bash
# Check cert-manager status
kubectl get pods -n cert-manager
kubectl logs -f deployment/cert-manager -n cert-manager

# Check certificate requests
kubectl get certificaterequests -n ai-system
kubectl describe certificaterequest <request-name> -n ai-system

# Check ACME challenges
kubectl get challenges -n ai-system
kubectl describe challenge <challenge-name> -n ai-system

# Manual certificate renewal
kubectl delete certificate r2r-tls -n ai-system
kubectl apply -f deployment/setup/azure/kubernetes/ingress/ssl-certificates.yaml
```

#### Let's Encrypt Rate Limits
```bash
# Check rate limit status
curl -s "https://crt.sh/?q=r2r.wingwork.com&output=json" | jq '. | length'

# Use staging environment temporarily
kubectl patch clusterissuer letsencrypt-prod --type='merge' -p='{"spec":{"acme":{"server":"https://acme-staging-v02.api.letsencrypt.org/directory"}}}'

# Switch back to production after rate limit resets
kubectl patch clusterissuer letsencrypt-prod --type='merge' -p='{"spec":{"acme":{"server":"https://acme-v02.api.letsencrypt.org/directory"}}}'
```

### Cloudflare Issues

#### DNS Propagation Problems
```bash
# Check DNS from multiple resolvers
dig @8.8.8.8 r2r.wingwork.com
dig @1.1.1.1 r2r.wingwork.com
dig @208.67.222.222 r2r.wingwork.com

# Force DNS cache refresh
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/purge_cache" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}'

# Check Cloudflare status
curl -s "https://www.cloudflarestatus.com/api/v2/summary.json" | jq .
```

## 📊 Performance Issues

### High CPU/Memory Usage

#### Identify Resource Hogs
```bash
# Check resource usage by pod
kubectl top pods -n ai-system --sort-by=cpu
kubectl top pods -n ai-system --sort-by=memory

# Check historical resource usage
kubectl exec -it prometheus-0 -n monitoring -- promtool query instant \
  'sum(rate(container_cpu_usage_seconds_total{namespace="ai-system"}[5m])) by (pod)'

# Check for memory leaks
kubectl exec -it <pod-name> -n ai-system -- ps aux
kubectl exec -it <pod-name> -n ai-system -- free -h
```

#### Scale Resources
```bash
# Horizontal scaling
kubectl scale deployment r2r --replicas=5 -n ai-system

# Vertical scaling
kubectl patch deployment r2r -n ai-system -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "r2r",
          "resources": {
            "requests": {"cpu": "1000m", "memory": "2Gi"},
            "limits": {"cpu": "2000m", "memory": "4Gi"}
          }
        }]
      }
    }
  }
}'

# Auto-scaling
kubectl autoscale deployment r2r --cpu-percent=70 --min=3 --max=10 -n ai-system
```

### Slow API Response Times

#### Profile Application Performance
```bash
# Check API response times
curl -w "@curl-format.txt" -o /dev/null -s https://r2r.wingwork.com/v3/health

# Check database query performance
kubectl exec -it postgresql-0 -n ai-system -- psql -U postgres -d r2r -c "
SELECT query, mean_time, calls, total_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;"

# Check application logs for slow requests
kubectl logs -f deployment/r2r -n ai-system | grep -E "(slow|timeout|error)"
```

#### Optimize Performance
```bash
# Enable connection pooling
kubectl patch configmap r2r-configmap -n ai-system --patch '{"data":{"DATABASE_POOL_SIZE":"20","DATABASE_MAX_OVERFLOW":"10"}}'

# Restart application to apply changes
kubectl rollout restart deployment/r2r -n ai-system

# Implement caching
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: ai-system
data:
  redis.conf: |
    maxmemory 256mb
    maxmemory-policy allkeys-lru
EOF
```

## 🔒 Security Issues

### Authentication Problems

#### Azure AD Integration Issues
```bash
# Check Azure AD configuration
az ad app show --id $(terraform output -raw azure_ad_client_id)

# Test service principal authentication
az login --service-principal \
  --username $(terraform output -raw azure_ad_client_id) \
  --password $(terraform output -raw azure_ad_client_secret) \
  --tenant $(terraform output -raw azure_ad_tenant_id)

# Check RBAC assignments
kubectl get rolebindings,clusterrolebindings -o wide | grep r2r
```

#### Key Vault Access Issues
```bash
# Check Key Vault access policies
az keyvault show --name $(terraform output -raw key_vault_name) --query properties.accessPolicies

# Test Key Vault connectivity
az keyvault secret show --vault-name $(terraform output -raw key_vault_name) --name openai-api-key

# Check managed identity permissions
kubectl describe secretproviderclass azure-keyvault-secrets -n ai-system
```

### Network Security Issues

#### Pod Security Policy Violations
```bash
# Check pod security policy violations
kubectl get events --field-selector type=Warning | grep -i security

# Check security context
kubectl get pod <pod-name> -n ai-system -o jsonpath='{.spec.securityContext}'

# Fix security context issues
kubectl patch deployment r2r -n ai-system -p '{
  "spec": {
    "template": {
      "spec": {
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 1000,
          "fsGroup": 1000
        }
      }
    }
  }
}'
```

## 💾 Backup & Recovery

### Database Backup Issues

#### Manual Backup
```bash
# Create database backup
kubectl exec postgresql-0 -n ai-system -- pg_dump -U postgres r2r > r2r-backup-$(date +%Y%m%d).sql

# Upload to Azure Storage
az storage blob upload \
  --account-name $(terraform output -raw storage_account_name) \
  --container-name backups \
  --name r2r-backup-$(date +%Y%m%d).sql \
  --file r2r-backup-$(date +%Y%m%d).sql
```

#### Restore from Backup
```bash
# Download backup from Azure Storage
az storage blob download \
  --account-name $(terraform output -raw storage_account_name) \
  --container-name backups \
  --name r2r-backup-20231201.sql \
  --file restore-backup.sql

# Restore database
kubectl exec -i postgresql-0 -n ai-system -- psql -U postgres r2r < restore-backup.sql
```

### Configuration Backup

#### Backup Kubernetes Configurations
```bash
# Backup all configurations
kubectl get all,configmaps,secrets,ingress,pvc -n ai-system -o yaml > r2r-k8s-backup-$(date +%Y%m%d).yaml

# Backup specific resources
kubectl get configmaps -n ai-system -o yaml > configmaps-backup.yaml
kubectl get secrets -n ai-system -o yaml > secrets-backup.yaml
```

## 🔄 Maintenance Procedures

### Regular Maintenance Tasks

#### Weekly Tasks
```bash
#!/bin/bash
# weekly-maintenance.sh

echo "Starting weekly maintenance..."

# Check for updates
az aks get-upgrades --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_cluster_name)

# Clean up old images
kubectl exec deployment/r2r -n ai-system -- docker system prune -f

# Check certificate expiration
kubectl get certificates -n ai-system -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

# Update monitoring dashboards
curl -X POST http://admin:password@grafana:3000/api/dashboards/db -d @updated-dashboard.json

echo "Weekly maintenance complete."
```

#### Monthly Tasks
```bash
#!/bin/bash
# monthly-maintenance.sh

echo "Starting monthly maintenance..."

# Update base images
cd deployment/k8s/kustomizations
# Update image tags in kustomization.yaml
kubectl apply -k .

# Rotate secrets
# Generate new secrets and update in Key Vault

# Review and update scaling policies
kubectl get hpa -n ai-system
kubectl describe hpa r2r -n ai-system

# Cleanup old backups
az storage blob list --container-name backups --account-name $(terraform output -raw storage_account_name) --query "[?properties.lastModified < '$(date -d '30 days ago' -Iseconds)'].name" -o tsv | \
xargs -I {} az storage blob delete --container-name backups --name {} --account-name $(terraform output -raw storage_account_name)

echo "Monthly maintenance complete."
```

### Disaster Recovery

#### Complete System Recovery
```bash
#!/bin/bash
# disaster-recovery.sh

echo "Starting disaster recovery procedure..."

# 1. Recreate infrastructure
cd deployment/setup/azure/terraform
terraform apply -auto-approve

# 2. Wait for cluster to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=600s

# 3. Restore applications
kubectl apply -k deployment/setup/azure/kubernetes/azure-overlay/

# 4. Restore database
kubectl wait --for=condition=Ready pod/postgresql-0 -n ai-system --timeout=300s
kubectl exec -i postgresql-0 -n ai-system -- psql -U postgres r2r < latest-backup.sql

# 5. Verify application health
sleep 60
curl -f https://r2r.wingwork.com/v3/health || exit 1

echo "Disaster recovery complete."
```

## 📞 Emergency Procedures

### Critical Issue Response

#### Application Down
```bash
# Quick restart
kubectl rollout restart deployment/r2r -n ai-system

# Scale up replicas for redundancy
kubectl scale deployment r2r --replicas=5 -n ai-system

# Check external dependencies
curl -I https://api.openai.com/v1/models
curl -I https://api.anthropic.com/v1/messages

# Activate maintenance page
kubectl apply -f maintenance-page.yaml
```

#### Database Emergency
```bash
# Check database status
kubectl exec postgresql-0 -n ai-system -- pg_isready

# Emergency database restart
kubectl delete pod postgresql-0 -n ai-system

# Point to backup database
kubectl patch configmap r2r-configmap -n ai-system --patch '{"data":{"R2R_POSTGRES_HOST":"backup-db-host"}}'
kubectl rollout restart deployment/r2r -n ai-system
```

### Contact Information

For escalation, maintain a contact list:
- Azure Support: Create support ticket in Azure portal
- Infrastructure Team: [your-team-email]
- Application Team: [app-team-email]
- On-call Engineer: [on-call-number]
- DNS Provider (Cloudflare): Support portal

## 📚 Useful Resources

- [Azure Kubernetes Service Troubleshooting](https://docs.microsoft.com/en-us/azure/aks/troubleshooting)
- [Kubernetes Troubleshooting Guide](https://kubernetes.io/docs/tasks/debug-application-cluster/troubleshooting/)
- [cert-manager Troubleshooting](https://cert-manager.io/docs/faq/troubleshooting/)
- [Prometheus Troubleshooting](https://prometheus.io/docs/prometheus/latest/troubleshooting/)

---

**Remember**: Always test recovery procedures in a non-production environment first!