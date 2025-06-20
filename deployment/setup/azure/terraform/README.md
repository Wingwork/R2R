# Terraform Infrastructure Setup for R2R on Azure

This directory contains Terraform configuration to provision a production-ready Azure Kubernetes Service (AKS) cluster and supporting resources for R2R deployment.

## 📋 Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** >= 1.6 installed
3. **kubectl** installed
4. **Azure subscription** with appropriate permissions
5. **Azure AD group** for AKS administrators

## 🚀 Quick Start

### 1. Authenticate with Azure
```bash
# Login to Azure
az login

# List available subscriptions
az account list --output table

# Set the desired subscription
az account set --subscription "Your-Subscription-ID"

# Verify authentication
az account show
```

### 2. Create Azure AD Group for AKS Administrators
```bash
# Create an Azure AD group for AKS administrators
az ad group create \
  --display-name "AKS-R2R-Admins" \
  --mail-nickname "aks-r2r-admins" \
  --description "Administrators for R2R AKS cluster"

# Get the group Object ID (save this for terraform.tfvars)
az ad group show \
  --group "AKS-R2R-Admins" \
  --query objectId \
  --output tsv

# Add yourself to the group
az ad group member add \
  --group "AKS-R2R-Admins" \
  --member-id $(az ad signed-in-user show --query objectId --output tsv)
```

### 3. Configure Terraform Variables
```bash
# Copy the example terraform.tfvars file
cp terraform.tfvars.example terraform.tfvars

# Edit the file with your specific values
nano terraform.tfvars
```

### 4. Initialize and Deploy Infrastructure
```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 5. Configure kubectl
```bash
# Get the kubectl configuration command from Terraform output
terraform output kubectl_config_command

# Or directly configure kubectl
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Verify connection
kubectl get nodes
```

## 📁 File Structure

```
terraform/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── terraform.tfvars.example  # Example configuration
├── terraform.tfvars          # Your configuration (create from example)
└── README.md                 # This file
```

## 🏗️ Infrastructure Components

This Terraform configuration creates:

### Core Infrastructure
- **Resource Group**: Container for all resources
- **Virtual Network**: Isolated network environment
- **Subnets**: Separate subnets for AKS and Application Gateway
- **Network Security Groups**: Network traffic rules

### AKS Cluster
- **AKS Cluster**: Managed Kubernetes cluster
- **Default Node Pool**: System workloads (2-10 nodes, auto-scaling)
- **Application Node Pool**: Application workloads (1-8 nodes, auto-scaling)
- **Azure AD Integration**: RBAC with Azure AD groups
- **Monitoring**: Azure Monitor and Log Analytics integration

### Supporting Services
- **Azure Container Registry**: Private container registry
- **Azure Key Vault**: Secrets management
- **Log Analytics Workspace**: Centralized logging
- **Storage Account**: Persistent storage
- **Public IP**: External access endpoint
- **Application Gateway** (optional): Advanced routing and SSL termination

### Security Features
- **Network Policies**: Pod-to-pod communication control
- **Azure Policy**: Governance and compliance
- **RBAC**: Role-based access control
- **Private Cluster** (optional): Enhanced security
- **Managed Identity**: Secure service authentication

## ⚙️ Configuration Options

### Environment Configurations

#### Development Environment
```hcl
environment = "dev"
default_node_pool = {
  node_count = 1
  vm_size    = "Standard_B2s"
  min_count  = 1
  max_count  = 3
}
auto_shutdown_schedule = {
  enabled = true
  time    = "18:00"
  timezone = "UTC"
}
```

#### Production Environment
```hcl
environment = "prod"
enable_private_cluster = true
default_node_pool = {
  node_count = 3
  vm_size    = "Standard_D2s_v3"
  min_count  = 2
  max_count  = 10
}
backup_configuration = {
  enabled = true
  retention_days = 30
}
```

### VM Size Recommendations

| Environment | Default Node Pool | App Node Pool | Use Case |
|-------------|------------------|---------------|----------|
| Development | Standard_B2s (2 vCPU, 4GB) | Standard_B2s | Cost optimization |
| Staging | Standard_D2s_v3 (2 vCPU, 8GB) | Standard_D2s_v3 | Testing |
| Production | Standard_D2s_v3 (2 vCPU, 8GB) | Standard_D4s_v3 (4 vCPU, 16GB) | Performance |
| High Load | Standard_D4s_v3 (4 vCPU, 16GB) | Standard_D8s_v3 (8 vCPU, 32GB) | Heavy workloads |

## 🔒 Security Configuration

### Private Cluster Setup
For enhanced security, enable private cluster:

```hcl
enable_private_cluster = true
```

**Note**: Private clusters require additional network configuration and a jump host or VPN for access.

### Network Policies
Network policies are enabled by default to control pod-to-pod communication:

```hcl
enable_network_policies = true
```

### Key Vault Integration
Secrets are stored in Azure Key Vault and accessed via CSI driver:

```bash
# Example: Store an API key in Key Vault
az keyvault secret set \
  --vault-name $(terraform output -raw key_vault_name) \
  --name "openai-api-key" \
  --value "your-api-key"
```

## 💰 Cost Optimization

### Auto-scaling Configuration
```hcl
default_node_pool = {
  min_count = 1   # Minimum nodes during low usage
  max_count = 10  # Maximum nodes during high usage
}
```

### Spot Instances (Development Only)
```hcl
enable_spot_instances = true  # Not recommended for production
```

### Auto Shutdown (Development)
```hcl
auto_shutdown_schedule = {
  enabled  = true
  time     = "18:00"
  timezone = "UTC"
}
```

### Resource Tagging
All resources are tagged for cost tracking:

```hcl
common_tags = {
  Environment = "prod"
  CostCenter  = "engineering"
  Project     = "r2r-deployment"
}
```

## 📊 Monitoring and Logging

### Log Analytics Integration
All cluster logs are sent to Log Analytics:

```bash
# View cluster logs
az monitor log-analytics query \
  --workspace $(terraform output -raw log_analytics_workspace_id) \
  --analytics-query "ContainerLog | limit 10"
```

### Azure Monitor
Container insights are enabled for comprehensive monitoring:

```bash
# Open Azure Monitor in browser
echo $(terraform output -json monitoring_endpoints | jq -r '.azure_monitor')
```

## 🔄 Terraform State Management

### Local State (Development)
For development, Terraform state is stored locally. For production, use remote state:

### Remote State (Production)
Uncomment and configure the backend in `main.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "saterraformstate"
    container_name       = "tfstate"
    key                 = "r2r-prod.terraform.tfstate"
  }
}
```

Create the backend storage:

```bash
# Create resource group for Terraform state
az group create --name rg-terraform-state --location "East US"

# Create storage account for Terraform state
az storage account create \
  --resource-group rg-terraform-state \
  --name saterraformstate \
  --sku Standard_LRS \
  --encryption-services blob

# Create container for Terraform state
az storage container create \
  --name tfstate \
  --account-name saterraformstate
```

## 🚨 Important Notes

### Before Applying
1. **Review Costs**: Check Azure pricing calculator for estimated costs
2. **Set Quotas**: Ensure your subscription has sufficient quotas
3. **Backup Strategy**: Plan for data backup and disaster recovery
4. **Security Groups**: Configure Azure AD groups for proper access control

### After Applying
1. **Save Outputs**: Store important outputs (IPs, URLs, etc.)
2. **Configure DNS**: Set up DNS records for your domain
3. **SSL Certificates**: Configure SSL/TLS certificates
4. **Monitoring**: Set up alerts and monitoring dashboards

## 🛠️ Useful Commands

### Terraform Operations
```bash
# Format Terraform files
terraform fmt

# Validate configuration
terraform validate

# Plan with variable file
terraform plan -var-file="production.tfvars"

# Apply with auto-approve (be careful!)
terraform apply -auto-approve

# Destroy infrastructure (be very careful!)
terraform destroy
```

### Kubernetes Operations
```bash
# Get cluster info
kubectl cluster-info

# Get nodes
kubectl get nodes

# Get all resources
kubectl get all --all-namespaces

# Access Kubernetes dashboard (if enabled)
az aks browse --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_cluster_name)
```

### Azure Operations
```bash
# Login to ACR
$(terraform output -raw acr_login_command)

# List AKS clusters
az aks list --output table

# Get AKS credentials
$(terraform output -raw kubectl_config_command)

# Scale node pool
az aks nodepool scale \
  --resource-group $(terraform output -raw resource_group_name) \
  --cluster-name $(terraform output -raw aks_cluster_name) \
  --name apps \
  --node-count 5
```

## 🔧 Troubleshooting

### Common Issues

#### Authentication Issues
```bash
# Re-authenticate with Azure
az login --use-device-code

# Check current account
az account show
```

#### Terraform State Issues
```bash
# Refresh state
terraform refresh

# Import existing resource
terraform import azurerm_resource_group.main /subscriptions/{subscription-id}/resourceGroups/{resource-group-name}
```

#### AKS Access Issues
```bash
# Reset AKS credentials
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_cluster_name) --overwrite-existing

# Check RBAC permissions
kubectl auth can-i "*" "*" --all-namespaces
```

### Logs and Diagnostics
```bash
# View Terraform logs
export TF_LOG=DEBUG
terraform plan

# View AKS cluster diagnostics
az aks show --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_cluster_name)

# View node pool status
az aks nodepool list --resource-group $(terraform output -raw resource_group_name) --cluster-name $(terraform output -raw aks_cluster_name)
```

## 📚 Additional Resources

- [Azure Kubernetes Service Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)

## 🆘 Support

For issues with this Terraform configuration:
1. Check the troubleshooting section above
2. Review Azure activity logs in the portal
3. Check Terraform state and logs
4. Consult Azure documentation
5. Create an issue in the project repository

---

**Next Step**: After successful infrastructure deployment, proceed to [Kubernetes Deployment](../kubernetes/README.md)