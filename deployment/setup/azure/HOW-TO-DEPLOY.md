# 🚀 Complete Step-by-Step Guide: Deploy R2R on Azure

This guide walks you through deploying R2R on Azure from scratch. Follow every step carefully - this is designed for someone with basic computer science knowledge who is new to Azure and Kubernetes.

## 📋 Before You Start

### What You'll Need
- **Computer**: Windows, macOS, or Linux
- **Azure Account**: Free tier is fine to start ([sign up here](https://azure.microsoft.com/free/))
- **Cloudflare Account**: Free tier works ([sign up here](https://cloudflare.com))
- **Domain**: `wingwork.com` managed by Cloudflare
- **Time**: 2-3 hours for first deployment
- **Credit Card**: For Azure (free tier includes $200 credit)

### What You'll Build
- Production-ready R2R application
- Accessible at `https://r2r.wingwork.com`
- Auto-scaling Kubernetes cluster
- Monitoring dashboards
- Automatic SSL certificates
- Database with backups

---

## 📚 PHASE 1: Setup Your Local Environment

### Step 1.1: Install Required Software

#### For Windows Users:
```powershell
# Install Chocolatey (package manager)
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install required tools
choco install azure-cli terraform kubectl kubernetes-helm git jq curl -y

# Restart PowerShell after installation
```

#### For macOS Users:
```bash
# Install Homebrew (package manager)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install azure-cli terraform kubectl helm git jq curl
```

#### For Linux (Ubuntu/Debian) Users:
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install basic tools
sudo apt install -y curl wget unzip git jq

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Step 1.2: Verify Installations
```bash
# Check all tools are installed correctly
az --version
terraform --version
kubectl version --client
helm version
git --version
jq --version
curl --version
```

✅ **Expected Output**: All commands should return version numbers without errors.

### Step 1.3: Clone the R2R Repository
```bash
# Clone the repository
git clone https://github.com/SciPhi-AI/R2R.git
cd R2R

# Verify you're in the right place
ls deployment/setup/azure
```

✅ **Expected Output**: You should see `README.md`, `terraform/`, `kubernetes/`, etc.

---

## 🔑 PHASE 2: Configure Azure Account

### Step 2.1: Create Azure Account
1. Go to [Azure Portal](https://portal.azure.com)
2. Click "Create a free account"
3. Follow the signup process
4. **Important**: You'll need to provide a credit card, but won't be charged with free tier

### Step 2.2: Login to Azure CLI
```bash
# Login to Azure
az login
```

✅ **What Happens**: A browser window opens, you login, and see "You have logged in" message.

### Step 2.3: Set Up Your Subscription
```bash
# List available subscriptions
az account list --output table

# Set the subscription you want to use (usually there's only one)
az account set --subscription "Your-Subscription-Name-or-ID"

# Verify it's set correctly
az account show
```

✅ **Expected Output**: You should see your subscription details in JSON format.

### Step 2.4: Create Service Principal (Optional but Recommended)
```bash
# Create a service principal for Terraform
az ad sp create-for-rbac --name "terraform-r2r" --role Contributor --scopes /subscriptions/$(az account show --query id -o tsv)
```

✅ **Expected Output**: JSON with `appId`, `password`, `tenant` - **SAVE THESE VALUES**

---

## 🌐 PHASE 3: Configure Cloudflare

### Step 3.1: Set Up Domain in Cloudflare
1. Login to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Click "Add a Site"
3. Enter your domain: `wingwork.com`
4. Choose the Free plan
5. Update your domain's nameservers to point to Cloudflare (check with your domain registrar)

### Step 3.2: Get Cloudflare API Credentials
1. In Cloudflare Dashboard, go to **My Profile** → **API Tokens**
2. Click **Create Token**
3. Use **Custom Token** template
4. Set permissions:
   - **Zone:Zone:Read**
   - **Zone:DNS:Edit**
   - **Zone:Zone Settings:Edit**
5. Set Zone Resources: **Include - All zones**
6. Click **Continue to Summary** → **Create Token**
7. **SAVE THE TOKEN** - you can't see it again!

### Step 3.3: Get Zone ID
1. In Cloudflare Dashboard, click on your domain (`wingwork.com`)
2. In the right sidebar, copy the **Zone ID**
3. **SAVE THIS VALUE**

### Step 3.4: Set Environment Variables
```bash
# Add these to your shell profile (~/.bashrc, ~/.zshrc, or ~/.profile)
export CLOUDFLARE_API_TOKEN="your-api-token-here"
export CLOUDFLARE_ZONE_ID="your-zone-id-here"

# Reload your shell or run:
source ~/.bashrc  # or ~/.zshrc
```

✅ **Test Cloudflare Setup**:
```bash
# This should return your zone information
curl -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

---

## ⚙️ PHASE 4: Configure Your Deployment

### Step 4.1: Copy Configuration Template
```bash
# Navigate to the Azure deployment directory
cd deployment/setup/azure/terraform

# Copy the configuration template
cp terraform.tfvars.example terraform.tfvars
```

### Step 4.2: Edit Configuration File
```bash
# Open the configuration file in your preferred editor
nano terraform.tfvars
# or
code terraform.tfvars
# or
vim terraform.tfvars
```

### Step 4.3: Fill in Required Values

**Edit these lines in `terraform.tfvars`:**

```hcl
# Basic Configuration
environment         = "prod"
application_name    = "r2r"
location           = "East US"  # Change to your preferred region
resource_group_name = "rg-r2r-prod"

# Domain Configuration  
domain_name = "r2r.wingwork.com"

# IMPORTANT: Get your Azure AD group Object ID
# Run this command and paste the result:
# az ad group create --display-name "AKS-R2R-Admins" --mail-nickname "aks-r2r-admins"
# az ad group show --group "AKS-R2R-Admins" --query objectId -o tsv
aks_admin_group_object_ids = [
  "PASTE-YOUR-GROUP-OBJECT-ID-HERE"
]

# Cloudflare Configuration
cloudflare_config = {
  zone_id    = "your-zone-id-from-step-3.3"
  api_token  = "your-api-token-from-step-3.2"
  enable_cdn = true
  enable_waf = true
}
```

### Step 4.4: Create Azure AD Group for AKS Access
```bash
# Create admin group for AKS
az ad group create --display-name "AKS-R2R-Admins" --mail-nickname "aks-r2r-admins"

# Get the group Object ID
GROUP_ID=$(az ad group show --group "AKS-R2R-Admins" --query objectId -o tsv)
echo "Your Group Object ID: $GROUP_ID"

# Add yourself to the group
az ad group member add --group "AKS-R2R-Admins" --member-id $(az ad signed-in-user show --query objectId -o tsv)
```

✅ **Copy the Group Object ID and paste it into your `terraform.tfvars` file.**

### Step 4.5: Configure API Keys (Secure Method)
```bash
# Create a separate file for sensitive values
cat > terraform.tfvars.secrets << 'EOF'
# API Keys - DO NOT COMMIT TO GIT
api_keys = {
  openai_api_key       = "sk-your-openai-key-here"
  anthropic_api_key    = "sk-ant-your-anthropic-key-here"
  azure_api_key        = ""  # Optional
  google_api_key       = ""  # Optional
  github_client_id     = ""  # Optional
  github_client_secret = ""  # Optional
}
EOF

# Add secrets file to .gitignore
echo "terraform.tfvars.secrets" >> .gitignore
echo "terraform.tfvars" >> .gitignore
```

### Step 4.6: Set Up Kubernetes Secrets
```bash
# Navigate to Kubernetes overlay directory
cd ../kubernetes/azure-overlay

# Copy secrets template
cp azure-secrets.yaml.example azure-secrets.yaml

# Edit the secrets file
nano azure-secrets.yaml
```

**Edit the following values in `azure-secrets.yaml`:**
```yaml
stringData:
  # At minimum, you need these:
  OPENAI_API_KEY: "sk-your-openai-key-here"
  ANTHROPIC_API_KEY: "sk-ant-your-anthropic-key-here"  # Optional
  R2R_SECRET_KEY: "generate-random-32-char-string"     # Generate below
```

**Generate a secure secret key:**
```bash
# Generate a random secret key
openssl rand -base64 32
# Copy this value to R2R_SECRET_KEY in azure-secrets.yaml
```

### Step 4.7: Configure External PostgreSQL Database
```bash
# Set PostgreSQL configuration via environment variable for security
export TF_VAR_postgres_config='{
  "host": "your-postgres-host-or-ip",
  "port": 5432,
  "username": "r2r_user",
  "password": "your-secure-password",
  "database": "r2r"
}'

# Alternatively, edit terraform.tfvars directly (less secure)
# Update the postgres_config section with your database details
```

**Important**: Make sure your PostgreSQL database:
- Has the `pgvector` extension installed
- Has a database named `r2r` (or update the config)
- Has a user `r2r_user` with full access to the `r2r` database
- Is accessible from your Azure AKS cluster (network connectivity)

---

## 🏗️ PHASE 5: Deploy Infrastructure

### Step 5.1: Initialize Terraform
```bash
# Go back to terraform directory
cd ../../terraform

# Initialize Terraform
terraform init
```

✅ **Expected Output**: 
```
Terraform has been successfully initialized!
```

### Step 5.2: Validate Configuration
```bash
# Validate the configuration
terraform validate
```

✅ **Expected Output**: 
```
Success! The configuration is valid.
```

### Step 5.3: Plan the Deployment
```bash
# See what will be created
terraform plan -var-file="terraform.tfvars.secrets"
```

✅ **Expected Output**: A list of ~20-30 resources that will be created, including:
- Resource group
- Virtual network
- AKS cluster
- Storage account
- Key vault
- Public IP

### Step 5.4: Deploy Infrastructure
```bash
# Deploy the infrastructure (this takes 15-20 minutes)
terraform apply -var-file="terraform.tfvars.secrets"
```

**When prompted, type `yes` to confirm.**

✅ **Expected Output**: 
```
Apply complete! Resources: 25 added, 0 changed, 0 destroyed.
```

🕐 **This step takes 15-20 minutes** - Azure is creating your Kubernetes cluster.

### Step 5.5: Configure kubectl
```bash
# Get cluster credentials
RG_NAME=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw aks_cluster_name)

az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME --overwrite-existing

# Test cluster connection
kubectl get nodes
```

✅ **Expected Output**: List of 3 nodes in "Ready" status.

---

## 🚀 PHASE 6: Deploy the Application

### Step 6.1: Deploy Base Infrastructure
```bash
# Add Helm repositories
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values ../kubernetes/values/ingress-nginx.yaml \
  --wait --timeout=10m
```

✅ **Expected Output**: 
```
NAME: ingress-nginx
STATUS: deployed
```

### Step 6.2: Install cert-manager
```bash
# Install cert-manager for SSL certificates
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --values ../kubernetes/values/cert-manager.yaml \
  --wait --timeout=10m
```

✅ **Expected Output**: 
```
NAME: cert-manager
STATUS: deployed
```

### Step 6.3: Deploy R2R Application
```bash
# Navigate to the overlay directory
cd ../kubernetes/azure-overlay

# Apply the Azure-specific overlay (this extends the base R2R configuration)
kubectl apply -k .

# Wait for the database initialization job to complete
kubectl wait --for=condition=complete --timeout=300s job/create-r2r-database -n ai-system

# Wait for deployments to be ready (this can take 10-15 minutes)
kubectl wait --for=condition=available --timeout=900s deployment --all -n ai-system
```

✅ **Expected Output**: All deployments show as "available".

**Note**: The deployment includes:
- **External PostgreSQL** database (your existing database server)
- **Hatchet PostgreSQL** inside Kubernetes for workflow data  
- **Environment variables** automatically injected for database connectivity
- **Secrets** managed securely via Kubernetes

### Step 6.4: Check Application Status
```bash
# Check all pods are running
kubectl get pods -n ai-system

# Check services
kubectl get services -n ai-system

# Check ingress
kubectl get ingress -n ai-system
```

✅ **Expected Output**: All pods should be "Running" or "Completed".

---

## 🌐 PHASE 7: Configure DNS and SSL

### Step 7.1: Get Azure Public IP
```bash
# Go back to terraform directory
cd ../../terraform

# Get the public IP address
PUBLIC_IP=$(terraform output -raw public_ip_address)
echo "Your Azure Public IP: $PUBLIC_IP"
```

### Step 7.2: Configure DNS Record
```bash
# Create DNS record pointing r2r.wingwork.com to Azure IP
curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{
    \"type\": \"A\",
    \"name\": \"r2r\",
    \"content\": \"$PUBLIC_IP\",
    \"ttl\": 300,
    \"proxied\": true,
    \"comment\": \"R2R application on Azure AKS\"
  }"
```

✅ **Expected Output**: JSON response with `"success": true`.

### Step 7.3: Deploy SSL Certificates
```bash
# Go back to Kubernetes directory
cd ../kubernetes

# Deploy ingress with SSL configuration
kubectl apply -f ingress.yaml
```

### Step 7.4: Wait for SSL Certificate
```bash
# Check certificate status (this can take 5-10 minutes)
kubectl get certificates -n ai-system

# Watch certificate creation
kubectl get challenges -n ai-system
kubectl describe certificate r2r-tls -n ai-system
```

✅ **Expected Output**: Certificate status shows "True" under READY column.

---

## 📊 PHASE 8: Deploy Monitoring (Optional)

### Step 8.1: Install Prometheus Stack
```bash
# Add Prometheus repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install monitoring stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values ../monitoring/prometheus-values.yaml \
  --wait --timeout=15m
```

### Step 8.2: Get Grafana Password
```bash
# Get Grafana admin password
kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode
echo  # Just adds a newline
```

✅ **SAVE THIS PASSWORD** - you'll need it to login to Grafana.

---

## ✅ PHASE 9: Verify Your Deployment

### Step 9.1: Test DNS Resolution
```bash
# Test DNS resolution
nslookup r2r.wingwork.com

# Test from different DNS servers
dig @8.8.8.8 r2r.wingwork.com
dig @1.1.1.1 r2r.wingwork.com
```

✅ **Expected Output**: Both should return your Azure public IP address.

### Step 9.2: Test Application
```bash
# Test health endpoint
curl https://r2r.wingwork.com/v3/health

# Test with verbose output
curl -I https://r2r.wingwork.com/v3/health
```

✅ **Expected Output**: 
```json
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Step 9.3: Access Web Interfaces

Open these URLs in your browser:

1. **Main Application**: https://r2r.wingwork.com
2. **Grafana Monitoring**: https://r2r.wingwork.com/grafana
   - Username: `admin`
   - Password: (from Step 8.2)
3. **Prometheus Metrics**: https://r2r.wingwork.com/prometheus
4. **Hatchet Workflows**: https://r2r.wingwork.com/hatchet

✅ **All URLs should load without SSL warnings.**

---

## 🎉 SUCCESS! Your Deployment is Complete

### What You've Built:
- ✅ Production Kubernetes cluster on Azure
- ✅ R2R application accessible at https://r2r.wingwork.com
- ✅ Automatic SSL certificates
- ✅ Auto-scaling (2-10 nodes based on load)
- ✅ Monitoring with Prometheus and Grafana
- ✅ Database with automatic backups
- ✅ Workflow engine (Hatchet)
- ✅ CDN and security via Cloudflare

### Your URLs:
- **Main App**: https://r2r.wingwork.com
- **API Docs**: https://r2r.wingwork.com/docs
- **Health Check**: https://r2r.wingwork.com/v3/health
- **Monitoring**: https://r2r.wingwork.com/grafana
- **Metrics**: https://r2r.wingwork.com/prometheus
- **Workflows**: https://r2r.wingwork.com/hatchet

---

## 🔧 Common Post-Deployment Tasks

### Check Application Logs
```bash
# View R2R application logs
kubectl logs -f deployment/r2r -n ai-system

# View all pods in the namespace
kubectl get pods -n ai-system
```

### Scale the Application
```bash
# Scale to more replicas for high traffic
kubectl scale deployment r2r --replicas=5 -n ai-system

# Enable auto-scaling
kubectl autoscale deployment r2r --cpu-percent=70 --min=3 --max=10 -n ai-system
```

### Update the Application
```bash
# Update to a new version
cd deployment/k8s/kustomizations
# Edit image tags in kustomization.yaml
kubectl apply -k ../../setup/azure/kubernetes/azure-overlay/
```

### Monitor Resources
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n ai-system

# Check cluster events
kubectl get events --sort-by=.metadata.creationTimestamp
```

---

## 🚨 If Something Goes Wrong

### Quick Diagnostics
```bash
# Run the health check script
../scripts/deploy-r2r.sh --phase all --dry-run

# Check infrastructure
cd terraform && terraform show

# Check Kubernetes
kubectl get pods --all-namespaces
kubectl describe pod <failing-pod-name> -n ai-system
```

### Common Issues and Solutions

#### DNS Not Resolving
```bash
# Check Cloudflare record
curl -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=r2r" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# Update DNS record if needed
PUBLIC_IP=$(cd terraform && terraform output -raw public_ip_address)
# Use the script from Phase 7.2 to update
```

#### SSL Certificate Not Working
```bash
# Check certificate status
kubectl get certificates -n ai-system
kubectl describe certificate r2r-tls -n ai-system

# Force certificate renewal
kubectl delete certificate r2r-tls -n ai-system
kubectl apply -f kubernetes/ingress.yaml
```

#### Application Not Starting
```bash
# Check pod logs
kubectl logs -f deployment/r2r -n ai-system

# Check pod description
kubectl describe pod $(kubectl get pods -n ai-system -l app=r2r -o jsonpath='{.items[0].metadata.name}') -n ai-system

# Check secrets
kubectl get secrets -n ai-system
```

#### Out of Resources
```bash
# Check node resource usage
kubectl describe nodes

# Check if cluster autoscaler is working
kubectl get pods -n kube-system | grep cluster-autoscaler
kubectl logs -f deployment/cluster-autoscaler -n kube-system
```

---

## 💰 Managing Costs

### Monitor Your Spending
1. Go to [Azure Cost Management](https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview)
2. Set up budget alerts
3. Check daily spending

### Scale Down for Development
```bash
# Scale down to minimum for cost savings
kubectl scale deployment r2r --replicas=1 -n ai-system
kubectl scale statefulset postgresql --replicas=1 -n ai-system

# Scale down AKS nodes
az aks nodepool scale --name agentpool --cluster-name $CLUSTER_NAME --resource-group $RG_NAME --node-count 1
```

### Auto-Shutdown (Development Only)
```bash
# Add to your terraform.tfvars for dev environment:
auto_shutdown_schedule = {
  enabled  = true
  time     = "18:00"
  timezone = "UTC"
}
```

---

## 📚 Next Steps

### Learn More
- Read [deployment/setup/azure/docs/troubleshooting.md](docs/troubleshooting.md)
- Explore [R2R Documentation](https://r2r-docs.sciphi.ai/)
- Learn [Kubernetes Basics](https://kubernetes.io/docs/tutorials/)
- Understand [Azure AKS](https://docs.microsoft.com/en-us/azure/aks/)

### Customize Your Deployment
- Add more LLM providers
- Configure additional monitoring
- Set up CI/CD pipelines
- Add custom domains
- Implement backup strategies

### Get Support
- **R2R Issues**: [GitHub Issues](https://github.com/SciPhi-AI/R2R/issues)
- **Azure Support**: Azure Portal → Support
- **Community**: Join R2R Discord/Slack

---

**🎊 Congratulations! You've successfully deployed R2R on Azure!** 

Your application is now running in production with enterprise-grade infrastructure, monitoring, and security. You can now start uploading documents and building RAG applications with R2R.