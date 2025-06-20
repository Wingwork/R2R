# Azure Kubernetes Deployment Guide for R2R

This guide covers deploying R2R on Azure Kubernetes Service (AKS) using the existing Kubernetes configurations with Azure-specific overlays.

## 📋 Prerequisites

1. **Infrastructure deployed** via Terraform (see [terraform/README.md](../terraform/README.md))
2. **kubectl configured** to connect to your AKS cluster
3. **Helm installed** (version 3.x)
4. **Kustomize** (included with kubectl 1.14+)

## 🏗️ Architecture Overview

This setup extends the existing `deployment/k8s/kustomizations/` with Azure-specific configurations:

```
R2R Deployment Structure:
├── deployment/k8s/kustomizations/     # Base configurations (existing)
│   ├── kustomization.yaml            # Base kustomization
│   ├── helm-values_*.yaml            # Helm values
│   └── include/                      # Base manifests
└── deployment/setup/azure/           # Azure-specific extensions
    ├── kubernetes/                   # Azure overlays
    │   ├── azure-overlay/            # Azure-specific kustomize overlay
    │   ├── ingress/                  # Azure Load Balancer & Ingress
    │   └── monitoring/               # Monitoring integration
    └── terraform/                    # Infrastructure
```

## 🚀 Quick Start

### 1. Verify AKS Connection
```bash
# Get AKS credentials (from Terraform output)
az aks get-credentials \
  --resource-group $(cd ../terraform && terraform output -raw resource_group_name) \
  --name $(cd ../terraform && terraform output -raw aks_cluster_name)

# Verify connection
kubectl get nodes
kubectl cluster-info
```

### 2. Prepare Azure-specific Configuration
```bash
# Navigate to the repository root
cd /path/to/R2R

# Copy Azure secrets template
cp deployment/setup/azure/kubernetes/azure-overlay/secrets.yaml.example \
   deployment/setup/azure/kubernetes/azure-overlay/secrets.yaml

# Edit with your values
nano deployment/setup/azure/kubernetes/azure-overlay/secrets.yaml
```

### 3. Deploy Base R2R Application
```bash
# Deploy using existing kustomization with Azure overlay
kubectl apply -k deployment/setup/azure/kubernetes/azure-overlay/

# Monitor deployment
kubectl get pods -n ai-system -w
```

### 4. Set up Ingress and DNS
```bash
# Deploy Azure-specific ingress
kubectl apply -f deployment/setup/azure/kubernetes/ingress/

# Follow DNS configuration guide
# See: ../docs/cloudflare-dns.md
```

### 5. Install Monitoring (Optional)
```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install monitoring stack
kubectl apply -k deployment/setup/azure/kubernetes/monitoring/
```

## 📁 Azure Extension Structure

```
deployment/setup/azure/kubernetes/
├── azure-overlay/              # Main Azure overlay
│   ├── kustomization.yaml     # Extends base kustomization
│   ├── secrets.yaml.example   # Azure-specific secrets template
│   ├── azure-patches.yaml     # Azure-specific patches
│   └── azure-configmap.yaml   # Azure environment variables
├── ingress/                   # Azure Load Balancer & Ingress
│   ├── ingress-controller.yaml
│   ├── ssl-certificates.yaml
│   └── azure-ingress.yaml
└── monitoring/                # Monitoring overlay
    ├── kustomization.yaml
    ├── prometheus-azure.yaml
    └── grafana-azure.yaml
```

## ⚙️ Azure-Specific Configurations

### Azure Overlay Kustomization

The Azure overlay extends the base configuration:

```yaml
# deployment/setup/azure/kubernetes/azure-overlay/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Use existing base configuration
resources:
- ../../../k8s/kustomizations

# Override namespace to match existing
namespace: ai-system

# Azure-specific patches
patches:
- path: azure-patches.yaml
  target:
    kind: Service
    name: r2r

# Azure-specific resources
resources:
- azure-configmap.yaml

# Azure-specific secrets
secretGenerator:
- name: azure-secrets
  files:
  - azure-storage-key=azure-storage.key
  - azure-keyvault-secret=azure-keyvault.secret

# Image overrides for Azure Container Registry (if using)
images:
- name: ragtoriches/prod
  newName: your-acr.azurecr.io/r2r/app
  newTag: latest
```

### Azure Load Balancer Integration

```yaml
# Azure-specific service patches
apiVersion: v1
kind: Service
metadata:
  name: r2r
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-sku: "standard"
    service.beta.kubernetes.io/azure-load-balancer-external: "true"
    service.beta.kubernetes.io/azure-dns-label-name: "r2r-api"
spec:
  type: LoadBalancer
  loadBalancerSourceRanges:
  - 0.0.0.0/0  # Restrict as needed
```

### Azure Key Vault Integration

```yaml
# SecretProviderClass for Azure Key Vault
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: r2r-azure-secrets
  namespace: ai-system
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: ""  # From Terraform output
    keyvaultName: ""            # From Terraform output
    objects: |
      array:
        - objectName: openai-api-key
          objectType: secret
        - objectName: postgres-password
          objectType: secret
```

## 🔧 Step-by-Step Deployment

### Step 1: Prepare Azure Configuration
```bash
# Create Azure-specific secrets
kubectl create secret generic azure-storage-config \
  --from-literal=account-name="$(cd ../terraform && terraform output -raw storage_account_name)" \
  --from-literal=account-key="$(cd ../terraform && terraform output -raw storage_account_primary_access_key)" \
  -n ai-system

# Create Azure Key Vault secret (if using)
kubectl create secret generic azure-keyvault-config \
  --from-literal=vault-name="$(cd ../terraform && terraform output -raw key_vault_name)" \
  --from-literal=tenant-id="$(cd ../terraform && terraform output -raw aks_identity_tenant_id)" \
  -n ai-system
```

### Step 2: Deploy with Azure Overlay
```bash
# Deploy R2R with Azure-specific configurations
kubectl apply -k deployment/setup/azure/kubernetes/azure-overlay/

# Verify deployment
kubectl get pods -n ai-system
kubectl get services -n ai-system
kubectl get ingress -n ai-system
```

### Step 3: Configure External Access
```bash
# Get external IP from Terraform
EXTERNAL_IP=$(cd ../terraform && terraform output -raw public_ip_address)
echo "External IP: $EXTERNAL_IP"

# Update DNS records to point r2r.wingwork.com to $EXTERNAL_IP
# See: ../docs/cloudflare-dns.md
```

### Step 4: Verify Application
```bash
# Test internal connectivity
kubectl port-forward svc/r2r 7272:7272 -n ai-system &
curl http://localhost:7272/v3/health

# Test external connectivity (after DNS setup)
curl https://r2r.wingwork.com/v3/health
```

## 📊 Monitoring Integration

### Extend Monitoring to Use Existing Setup
```bash
# Deploy monitoring that integrates with existing metrics
kubectl apply -k deployment/setup/azure/kubernetes/monitoring/

# The monitoring overlay extends the base monitoring with:
# - Azure-specific service monitors
# - Azure Log Analytics integration
# - Azure-specific dashboards
```

### Azure Monitor Integration
```bash
# Enable Azure Monitor for containers (if not done via Terraform)
az aks enable-addons \
  --addons monitoring \
  --name $(cd ../terraform && terraform output -raw aks_cluster_name) \
  --resource-group $(cd ../terraform && terraform output -raw resource_group_name) \
  --workspace-resource-id $(cd ../terraform && terraform output -raw log_analytics_workspace_id)
```

## 🔐 Security Best Practices

### Use Existing Security Configurations
The base R2R deployment already includes:
- Network policies
- Pod security standards
- RBAC configurations

Azure overlay adds:
- Azure Key Vault integration
- Azure AD authentication
- Azure policy compliance

### Azure-Specific Security
```bash
# Enable Azure Policy for Kubernetes
az aks enable-addons \
  --addons azure-policy \
  --name $(cd ../terraform && terraform output -raw aks_cluster_name) \
  --resource-group $(cd ../terraform && terraform output -raw resource_group_name)
```

## 🔄 Scaling and Updates

### Using Existing Scaling Configuration
The base deployment includes HPA configurations. Azure overlay adds:
- Integration with Azure Monitor metrics
- Custom scaling based on Azure-specific metrics

### Update Application
```bash
# Update image versions in base kustomization
cd deployment/k8s/kustomizations
# Edit image tags in kustomization.yaml

# Apply updates
kubectl apply -k deployment/setup/azure/kubernetes/azure-overlay/

# Monitor rollout
kubectl rollout status deployment/r2r -n ai-system
```

## 🛠️ Useful Commands

### Working with Existing Structure
```bash
# Build and preview Azure overlay
kubectl kustomize deployment/setup/azure/kubernetes/azure-overlay/

# Compare with base configuration
kubectl kustomize deployment/k8s/kustomizations/ > base.yaml
kubectl kustomize deployment/setup/azure/kubernetes/azure-overlay/ > azure.yaml
diff base.yaml azure.yaml

# Validate overlay
kubectl apply --dry-run=client -k deployment/setup/azure/kubernetes/azure-overlay/
```

### Azure-Specific Operations
```bash
# Get Azure resource information
az aks show \
  --name $(cd ../terraform && terraform output -raw aks_cluster_name) \
  --resource-group $(cd ../terraform && terraform output -raw resource_group_name)

# Check Azure Monitor logs
az monitor log-analytics query \
  --workspace $(cd ../terraform && terraform output -raw log_analytics_workspace_id) \
  --analytics-query "ContainerLog | where Name contains 'r2r' | limit 10"

# Update ACR credentials
az acr login --name $(cd ../terraform && terraform output -raw acr_login_server)
```

## 🚨 Troubleshooting

### Integration Issues
```bash
# Check if base configurations are applied correctly
kubectl get -k deployment/k8s/kustomizations/ -n ai-system

# Verify Azure overlay differences
kubectl diff -k deployment/setup/azure/kubernetes/azure-overlay/

# Check Azure-specific resources
kubectl get secrets -n ai-system | grep azure
kubectl get configmaps -n ai-system | grep azure
```

### Azure Load Balancer Issues
```bash
# Check service annotations
kubectl describe svc r2r -n ai-system

# Check Azure Load Balancer status
az network lb list --resource-group $(cd ../terraform && terraform output -raw aks_node_resource_group)

# Check public IP assignment
az network public-ip list --resource-group $(cd ../terraform && terraform output -raw aks_node_resource_group)
```

## 📚 Key Integration Points

1. **Reuses existing Helm charts** for Hatchet and PostgreSQL
2. **Extends existing ConfigMaps** with Azure-specific environment variables
3. **Patches existing services** for Azure Load Balancer integration
4. **Maintains existing namespace** (ai-system)
5. **Preserves existing image management** with optional ACR integration
6. **Extends existing monitoring** with Azure-specific metrics

## 🆘 Support

For Azure deployment issues:
1. Verify base R2R deployment works: `kubectl get pods -n ai-system`
2. Check Azure overlay application: `kubectl kustomize deployment/setup/azure/kubernetes/azure-overlay/`
3. Review Azure-specific logs: Check Azure Monitor and Log Analytics
4. Validate Terraform outputs: Ensure infrastructure is properly deployed

---

**Next Step**: After successful deployment, configure [DNS and SSL](../docs/cloudflare-dns.md)