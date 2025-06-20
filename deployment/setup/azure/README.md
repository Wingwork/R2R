# R2R Production Deployment on Azure Kubernetes Service (AKS)

This guide provides comprehensive instructions for deploying R2R at production quality on Azure Kubernetes Service (AKS) with proper networking, scaling, monitoring, and domain configuration.

## 🎯 What You'll Achieve

By following this guide, you'll have:
- A production-ready AKS cluster with auto-scaling
- R2R application accessible via `r2r.wingwork.com` with SSL/TLS
- Comprehensive monitoring with Prometheus and Grafana
- Infrastructure as Code using Terraform (cloud-agnostic)
- Proper security and networking configurations
- Automated certificate management

## 📋 Prerequisites

### Required Knowledge
- Basic understanding of command line interfaces
- Familiarity with YAML configuration files
- Basic networking concepts (DNS, SSL/TLS)
- Understanding of containerization concepts

### Required Accounts & Access
1. **Azure Account** with subscription (free tier available)
2. **Cloudflare Account** with domain `wingwork.com` managed
3. **GitHub Account** (for GitOps deployment)

### Required Tools Installation
Before starting, you'll need to install these tools on your local machine:

#### 1. Azure CLI
```bash
# macOS
brew install azure-cli

# Windows (PowerShell as Administrator)
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'

# Linux (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

#### 2. Terraform
```bash
# macOS
brew install terraform

# Windows (Chocolatey)
choco install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

#### 3. kubectl (Kubernetes CLI)
```bash
# macOS
brew install kubectl

# Windows
curl -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

#### 4. Helm (Kubernetes Package Manager)
```bash
# macOS
brew install helm

# Windows
choco install kubernetes-helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 5. Git
```bash
# macOS
brew install git

# Windows
# Download from https://git-scm.com/download/win

# Linux
sudo apt-get install git
```

## 🚀 Deployment Overview

The deployment process consists of 5 main phases:

1. **Infrastructure Setup** - Create AKS cluster and Azure resources
2. **Application Deployment** - Deploy R2R using Kubernetes
3. **Monitoring Setup** - Configure Prometheus and Grafana
4. **Domain Configuration** - Setup Cloudflare DNS and SSL
5. **Verification & Maintenance** - Test and maintain the deployment

## 📁 Directory Structure

```
deployment/setup/azure/
├── README.md                 # This file
├── terraform/               # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── kubernetes/              # K8s deployment files
│   ├── namespaces.yaml
│   ├── secrets.yaml
│   └── values/
├── monitoring/              # Monitoring setup
│   ├── prometheus/
│   └── grafana/
├── scripts/                 # Automation scripts
│   ├── setup.sh
│   ├── deploy.sh
│   └── cleanup.sh
└── docs/                   # Additional documentation
    ├── troubleshooting.md
    └── maintenance.md
```

## 🏗️ Quick Start Guide

### Step 1: Clone and Prepare Repository
```bash
git clone <r2r-repository-url>
cd R2R/deployment/setup/azure
```

### Step 2: Azure Authentication
```bash
# Login to Azure
az login

# Set your subscription (if you have multiple)
az account list --output table
az account set --subscription "Your-Subscription-ID"
```

### Step 3: Configure Environment
```bash
# Copy and edit Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit the file with your specific values
```

### Step 4: Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Step 5: Deploy Application
```bash
cd ../kubernetes
# Configure kubectl to use your AKS cluster
az aks get-credentials --resource-group rg-r2r-prod --name aks-r2r-prod
# Deploy the application
kubectl apply -f .
```

### Step 6: Configure Domain and SSL
Follow the detailed instructions in [Cloudflare Configuration Guide](docs/cloudflare-dns.md)

### Step 7: Setup Monitoring
```bash
cd ../monitoring
helm install prometheus prometheus/
helm install grafana grafana/
```

## 📊 Cost Estimation

### Azure Resources (Monthly Estimates)
- **AKS Cluster**: $150-300/month (depending on node size/count)
- **Load Balancer**: $25/month
- **Public IP**: $4/month
- **Storage**: $20-50/month
- **Network**: $10-30/month
- **Total**: ~$200-400/month

### Optimization Tips
- Use Azure Reserved Instances for 40-60% savings
- Enable auto-scaling to optimize costs during low usage
- Use Azure Spot Instances for non-critical workloads

## 🔒 Security Best Practices

This deployment includes:
- Network policies for pod-to-pod communication
- Azure Key Vault integration for secrets
- RBAC (Role-Based Access Control) configuration
- Private AKS cluster option (recommended for production)
- Web Application Firewall (WAF) protection
- SSL/TLS termination at load balancer

## 📈 Scaling & Performance

The setup includes:
- Horizontal Pod Autoscaler (HPA)
- Cluster Autoscaler for node scaling
- Resource limits and requests
- Persistent volume scaling
- Database connection pooling

## 🔄 GitOps Integration (Optional)

For advanced users, we provide ArgoCD integration for:
- Automated deployments from Git repositories
- Configuration drift detection
- Rollback capabilities
- Multi-environment management

## 📚 Next Steps

1. **[Infrastructure Setup](terraform/README.md)** - Detailed Terraform instructions
2. **[Application Deployment](kubernetes/README.md)** - Kubernetes deployment guide
3. **[Monitoring Setup](monitoring/README.md)** - Prometheus and Grafana configuration
4. **[Domain Configuration](docs/cloudflare-dns.md)** - Cloudflare DNS and SSL setup
5. **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## 🆘 Support & Resources

### Documentation Links
- [Azure Kubernetes Service (AKS)](https://docs.microsoft.com/en-us/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)

### Community Support
- R2R GitHub Issues
- Azure Community Forums
- Kubernetes Slack Channel

### Emergency Contacts
- Create monitoring alerts for critical issues
- Document escalation procedures
- Maintain disaster recovery procedures

---

## ⚠️ Important Notes

1. **Cost Management**: Monitor Azure costs regularly using Azure Cost Management
2. **Security Updates**: Keep all components updated with latest security patches
3. **Backup Strategy**: Implement regular backup procedures for data and configurations
4. **Testing**: Always test changes in a development environment first
5. **Documentation**: Keep deployment documentation updated with any customizations

---

**Ready to start?** Begin with the [Infrastructure Setup Guide](terraform/README.md)