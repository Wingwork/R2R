# R2R Production Deployment on Azure VM with Docker Compose

This guide provides comprehensive instructions for deploying R2R on Azure Virtual Machines using Docker Compose, with complete infrastructure setup including load balancing, SSL termination, DNS configuration, and monitoring.

## 🎯 What You'll Achieve

By following this guide, you'll have:
- Production-ready R2R application on Azure VM
- Complete infrastructure with load balancer, SSL, and DNS
- Application accessible via custom domain with HTTPS
- Auto-scaling VM instances behind load balancer
- Monitoring and health checks
- Secure networking with proper firewall rules

## 📋 Prerequisites

### Required Knowledge
- Basic understanding of command line interfaces
- Familiarity with Docker and Docker Compose
- Basic networking concepts (DNS, SSL/TLS, load balancing)
- Understanding of Azure cloud services

### Required Accounts & Access
1. **Azure Account** with subscription (free tier available)
2. **Domain Name** (e.g., `example.com`) managed by Cloudflare or use Azure DNS
3. **Cloudflare Account** (free tier works) for DNS management and CDN
4. **Email Address** for Let's Encrypt SSL certificates

### Required Tools Installation
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

## 🏗️ Architecture Overview

```
Internet → Azure Load Balancer → VM Scale Set → Docker Containers
    ↓              ↓              ↓           ↓
DNS Record → Public IP → VM Instances → R2R Services
```

### Services Deployed
- **R2R API**: Main application server (port 7272)
- **R2R Dashboard**: Web interface (port 7273)
- **PostgreSQL**: Database with pgvector extension
- **MinIO**: Object storage for files
- **Hatchet**: Workflow orchestration
- **Unstructured**: Document processing
- **Graph Clustering**: Advanced analytics
- **NGINX**: Reverse proxy and SSL termination

## 🚀 Phase 1: Azure Infrastructure Setup

### Step 1.1: Create Resource Group
```bash
# Login to Azure
az login

# Set variables
RESOURCE_GROUP="rg-r2r-prod"
LOCATION="eastus"
VM_NAME="r2r-vm"
DOMAIN_NAME="your-domain.com"  # Replace with your domain

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Step 1.2: Create Virtual Network
```bash
# Create virtual network
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name r2r-vnet \
  --address-prefix 10.0.0.0/16 \
  --subnet-name r2r-subnet \
  --subnet-prefix 10.0.1.0/24
```

### Step 1.3: Create Network Security Group
```bash
# Create NSG
az network nsg create \
  --resource-group $RESOURCE_GROUP \
  --name r2r-nsg

# Allow SSH
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name r2r-nsg \
  --name AllowSSH \
  --protocol tcp \
  --priority 1000 \
  --destination-port-range 22 \
  --source-address-prefixes '*'

# Allow HTTP
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name r2r-nsg \
  --name AllowHTTP \
  --protocol tcp \
  --priority 1001 \
  --destination-port-range 80 \
  --source-address-prefixes '*'

# Allow HTTPS
az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name r2r-nsg \
  --name AllowHTTPS \
  --protocol tcp \
  --priority 1002 \
  --destination-port-range 443 \
  --source-address-prefixes '*'
```

### Step 1.4: Create Public IP and Load Balancer
```bash
# Create public IP
az network public-ip create \
  --resource-group $RESOURCE_GROUP \
  --name r2r-public-ip \
  --sku Standard \
  --allocation-method Static \
  --dns-name r2r-${RANDOM}

# Create load balancer
az network lb create \
  --resource-group $RESOURCE_GROUP \
  --name r2r-lb \
  --sku Standard \
  --public-ip-address r2r-public-ip \
  --frontend-ip-name r2r-frontend \
  --backend-pool-name r2r-backend

# Create health probe
az network lb probe create \
  --resource-group $RESOURCE_GROUP \
  --lb-name r2r-lb \
  --name r2r-health-probe \
  --protocol http \
  --port 80 \
  --path /health

# Create load balancer rule for HTTP
az network lb rule create \
  --resource-group $RESOURCE_GROUP \
  --lb-name r2r-lb \
  --name r2r-http-rule \
  --protocol tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name r2r-frontend \
  --backend-pool-name r2r-backend \
  --probe-name r2r-health-probe

# Create load balancer rule for HTTPS
az network lb rule create \
  --resource-group $RESOURCE_GROUP \
  --lb-name r2r-lb \
  --name r2r-https-rule \
  --protocol tcp \
  --frontend-port 443 \
  --backend-port 443 \
  --frontend-ip-name r2r-frontend \
  --backend-pool-name r2r-backend \
  --probe-name r2r-health-probe
```

### Step 1.5: Create Virtual Machine Scale Set
```bash
# Create VM Scale Set
az vmss create \
  --resource-group $RESOURCE_GROUP \
  --name r2r-vmss \
  --image Ubuntu2204 \
  --vm-sku Standard_B2s \
  --instance-count 2 \
  --vnet-name r2r-vnet \
  --subnet r2r-subnet \
  --lb r2r-lb \
  --backend-pool-name r2r-backend \
  --nsg r2r-nsg \
  --admin-username azureuser \
  --generate-ssh-keys \
  --upgrade-policy-mode automatic

# Configure auto-scaling
az monitor autoscale create \
  --resource-group $RESOURCE_GROUP \
  --resource r2r-vmss \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name r2r-autoscale \
  --min-count 2 \
  --max-count 5 \
  --count 2

# Add scale-out rule
az monitor autoscale rule create \
  --resource-group $RESOURCE_GROUP \
  --autoscale-name r2r-autoscale \
  --condition "Percentage CPU > 70 avg 10m" \
  --scale out 1

# Add scale-in rule
az monitor autoscale rule create \
  --resource-group $RESOURCE_GROUP \
  --autoscale-name r2r-autoscale \
  --condition "Percentage CPU < 30 avg 10m" \
  --scale in 1
```

## 🔧 Phase 2: VM Configuration and Docker Setup

### Step 2.1: Connect to VM Instance
```bash
# Get public IP
PUBLIC_IP=$(az network public-ip show \
  --resource-group $RESOURCE_GROUP \
  --name r2r-public-ip \
  --query ipAddress \
  --output tsv)

echo "Public IP: $PUBLIC_IP"

# Connect to one of the VM instances
az vmss list-instance-connection-info \
  --resource-group $RESOURCE_GROUP \
  --name r2r-vmss

# SSH to the VM (replace with actual IP)
ssh azureuser@$PUBLIC_IP
```

### Step 2.2: Install Docker on VM
```bash
# Run these commands on the VM
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login again to apply docker group membership
exit
# SSH back in
ssh azureuser@$PUBLIC_IP
```

### Step 2.3: Setup R2R Application
```bash
# Clone R2R repository
git clone https://github.com/SciPhi-AI/R2R.git
cd R2R/docker

# Create environment files
mkdir -p env
```

### Step 2.4: Configure Environment Files
```bash
# Create production environment file
cat > env/prod.env << 'EOF'
# R2R Configuration
R2R_PROJECT_NAME=r2r-production
R2R_ENVIRONMENT=production

# Database Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_DB=r2r
POSTGRES_HOST=postgres
POSTGRES_PORT=5432

# MinIO Configuration
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123
MINIO_SECURE=false

# API Keys (Replace with your actual keys)
OPENAI_API_KEY=sk-your-openai-key-here
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key-here

# Hatchet Configuration
HATCHET_ENGINE_TOKEN=your-hatchet-token

# Security
R2R_SECRET_KEY=your-32-character-secret-key-here
R2R_CORS_ALLOWED_ORIGINS=https://your-domain.com

# Logging
R2R_LOG_LEVEL=INFO
R2R_LOG_FILE=/app/logs/r2r.log
EOF

# Create database environment file
cat > env/postgres.env << 'EOF'
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_DB=r2r
POSTGRES_HOST_AUTH_METHOD=md5
EOF

# Create MinIO environment file
cat > env/minio.env << 'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123
EOF

# Create Hatchet environment file
cat > env/hatchet.env << 'EOF'
HATCHET_ENGINE_TOKEN=your-hatchet-token
HATCHET_POSTGRES_USER=hatchet_user
HATCHET_POSTGRES_PASSWORD=hatchet_password
HATCHET_POSTGRES_DB=hatchet
HATCHET_POSTGRES_HOST=hatchet-postgres
HATCHET_POSTGRES_PORT=5432
EOF

# Create dashboard environment file
cat > env/r2r-dashboard.env << 'EOF'
NEXT_PUBLIC_API_URL=https://your-domain.com
NEXT_PUBLIC_APP_URL=https://your-domain.com
EOF
```

### Step 2.5: Create Docker Compose Configuration
```bash
# Create optimized docker-compose for production
cat > docker-compose.prod.yaml << 'EOF'
version: '3.8'

volumes:
  postgres_data:
  minio_data:
  hatchet_postgres_data:
  hatchet_rabbitmq_data:
  hatchet_rabbitmq_conf:
  hatchet_certs:
  hatchet_config:
  hatchet_api_key:
  nginx_ssl:
  logs:

services:
  # Database Services
  postgres:
    image: pgvector/pgvector:pg16
    env_file: ./env/postgres.env
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    command: >
      postgres
      -c max_connections=1024
      -c shared_buffers=256MB
      -c effective_cache_size=1GB

  minio:
    image: minio/minio
    env_file: ./env/minio.env
    volumes:
      - minio_data:/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    command: server /data --console-address ":9001"

  # Hatchet Services
  hatchet-postgres:
    image: postgres:latest
    env_file: ./env/hatchet.env
    volumes:
      - hatchet_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hatchet_user -d hatchet"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  hatchet-rabbitmq:
    image: "rabbitmq:3-management"
    hostname: "hatchet-rabbitmq"
    env_file: ./env/hatchet.env
    volumes:
      - hatchet_rabbitmq_data:/var/lib/rabbitmq
      - hatchet_rabbitmq_conf:/etc/rabbitmq/rabbitmq.conf
    healthcheck:
      test: ["CMD", "rabbitmqctl", "status"]
      interval: 10s
      timeout: 10s
      retries: 5
    restart: unless-stopped

  hatchet-migration:
    image: ghcr.io/hatchet-dev/hatchet/hatchet-migrate:v0.53.15
    env_file: ./env/hatchet.env
    depends_on:
      hatchet-postgres:
        condition: service_healthy
    restart: "no"

  hatchet-setup-config:
    image: ghcr.io/hatchet-dev/hatchet/hatchet-admin:v0.53.15
    command: /hatchet/hatchet-admin quickstart --skip certs --generated-config-dir /hatchet/config --overwrite=false
    env_file: ./env/hatchet.env
    volumes:
      - hatchet_certs:/hatchet/certs
      - hatchet_config:/hatchet/config
    depends_on:
      hatchet-migration:
        condition: service_completed_successfully
      hatchet-rabbitmq:
        condition: service_healthy
    restart: "no"

  hatchet-engine:
    image: ghcr.io/hatchet-dev/hatchet/hatchet-engine:v0.53.15
    command: /hatchet/hatchet-engine --config /hatchet/config
    env_file: ./env/hatchet.env
    volumes:
      - hatchet_certs:/hatchet/certs
      - hatchet_config:/hatchet/config
    depends_on:
      hatchet-setup-config:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8733/live"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  setup-token:
    image: ghcr.io/hatchet-dev/hatchet/hatchet-admin:v0.53.15
    command: sh /scripts/setup-token.sh
    volumes:
      - ./scripts:/scripts
      - hatchet_certs:/hatchet/certs
      - hatchet_config:/hatchet/config
      - hatchet_api_key:/hatchet_api_key
    depends_on:
      hatchet-setup-config:
        condition: service_completed_successfully
    restart: "no"

  # Application Services
  unstructured:
    image: ragtoriches/unst-prod
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7275/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  graph_clustering:
    image: ragtoriches/cluster-prod
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7276/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  r2r:
    image: sciphiai/r2r:latest
    env_file: ./env/prod.env
    command: sh /scripts/start-r2r.sh
    volumes:
      - ./user_configs:/app/user_configs
      - ./user_tools:/app/user_tools
      - hatchet_api_key:/hatchet_api_key:ro
      - ./scripts:/scripts
      - logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7272/v3/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      minio:
        condition: service_healthy
      setup-token:
        condition: service_completed_successfully
      unstructured:
        condition: service_healthy
      graph_clustering:
        condition: service_healthy

  r2r-dashboard:
    image: sciphiai/r2r-dashboard:1.0.3
    env_file: ./env/r2r-dashboard.env
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    depends_on:
      r2r:
        condition: service_healthy

  # Reverse Proxy and SSL
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - nginx_ssl:/etc/nginx/ssl
      - logs:/var/log/nginx
    depends_on:
      r2r:
        condition: service_healthy
      r2r-dashboard:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 10s
      timeout: 5s
      retries: 5

  # SSL Certificate Management
  certbot:
    image: certbot/certbot
    volumes:
      - nginx_ssl:/etc/letsencrypt
      - logs:/var/log/letsencrypt
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
    restart: unless-stopped
EOF
```

## 🌐 Phase 3: NGINX Configuration and SSL Setup

### Step 3.1: Create NGINX Configuration
```bash
# Create NGINX configuration file
cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream r2r_backend {
        server r2r:7272;
    }

    upstream dashboard_backend {
        server r2r-dashboard:3000;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=dashboard:10m rate=5r/s;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # HTTP to HTTPS redirect
    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    # HTTPS server
    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 'healthy\n';
            add_header Content-Type text/plain;
        }

        # R2R API endpoints
        location /v3/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://r2r_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
        }

        # Dashboard
        location / {
            limit_req zone=dashboard burst=10 nodelay;
            proxy_pass http://dashboard_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # WebSocket support for dashboard
        location /ws {
            proxy_pass http://dashboard_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
        }
    }
}
EOF
```

### Step 3.2: Setup Let's Encrypt Account and Obtain SSL Certificate
```bash
# Replace with your actual values
DOMAIN="your-domain.com"
EMAIL="your-email@example.com"

# Create SSL certificate directory
sudo mkdir -p /etc/letsencrypt

# First-time Let's Encrypt account registration
sudo docker run -it --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/lib/letsencrypt:/var/lib/letsencrypt \
  certbot/certbot register \
  --email $EMAIL \
  --agree-tos \
  --no-eff-email

# Obtain SSL certificate (make sure port 80 is available)
sudo docker run -it --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/lib/letsencrypt:/var/lib/letsencrypt \
  -p 80:80 \
  certbot/certbot certonly \
  --standalone \
  --email $EMAIL \
  --agree-tos \
  --no-eff-email \
  -d $DOMAIN

# Update nginx.conf with your domain
sed -i "s/your-domain.com/$DOMAIN/g" nginx.conf
```

**Important Notes:**
- Port 80 must be available and accessible from the internet for certificate validation
- If you get "port already in use" error, stop any running web services first
- The certificate is valid for 90 days and will auto-renew via the certbot container

## 🚀 Phase 4: Deployment and Configuration

### Step 4.1: Deploy the Application
```bash
# Pull all images
docker-compose -f docker-compose.prod.yaml pull

# Start the services
docker-compose -f docker-compose.prod.yaml up -d

# Check status
docker-compose -f docker-compose.prod.yaml ps
```

### Step 4.2: Configure VM Scale Set with Deployment Script
```bash
# Create deployment script for VM scale set
cat > deploy-to-vmss.sh << 'EOF'
#!/bin/bash

# Update VM Scale Set instances with the deployment
az vmss extension set \
  --resource-group $RESOURCE_GROUP \
  --vmss-name r2r-vmss \
  --name customScript \
  --publisher Microsoft.Azure.Extensions \
  --settings '{
    "fileUris": ["https://raw.githubusercontent.com/your-repo/r2r-deployment/main/setup.sh"],
    "commandToExecute": "bash setup.sh"
  }'

# Update all instances
az vmss update-instances \
  --resource-group $RESOURCE_GROUP \
  --name r2r-vmss \
  --instance-ids "*"
EOF

chmod +x deploy-to-vmss.sh
```

## 🌐 Phase 5: DNS Configuration

### Step 5.1: Get Azure Public IP Address
```bash
# Get the public IP address
PUBLIC_IP=$(az network public-ip show \
  --resource-group $RESOURCE_GROUP \
  --name r2r-public-ip \
  --query ipAddress \
  --output tsv)

echo "Your Azure Public IP: $PUBLIC_IP"
echo "You need to configure DNS to point $DOMAIN to $PUBLIC_IP"
```

### Step 5.2: Configure Cloudflare DNS (Recommended)

#### Option A: Using Cloudflare Dashboard (Manual)
1. **Login to Cloudflare Dashboard**
   - Go to [dash.cloudflare.com](https://dash.cloudflare.com)
   - Login with your Cloudflare account

2. **Select Your Domain**
   - Click on your domain (e.g., `example.com`)

3. **Add DNS Records**
   - Go to **DNS** → **Records**
   - Click **Add record**
   - **Type**: A
   - **Name**: `@` (for root domain) or `r2r` (for subdomain)
   - **IPv4 address**: Paste your Azure Public IP from Step 5.1
   - **Proxy status**: 🟠 Proxied (recommended for CDN and security)
   - **TTL**: Auto
   - Click **Save**

4. **Add WWW Record (Optional)**
   - Click **Add record**
   - **Type**: CNAME
   - **Name**: `www`
   - **Target**: `your-domain.com`
   - **Proxy status**: 🟠 Proxied
   - Click **Save**

#### Option B: Using Cloudflare API (Automated)
```bash
# Set your Cloudflare credentials
CLOUDFLARE_API_TOKEN="your-api-token-here"
CLOUDFLARE_ZONE_ID="your-zone-id-here"
DOMAIN_NAME="your-domain.com"

# Create A record for root domain
curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{
    \"type\": \"A\",
    \"name\": \"@\",
    \"content\": \"$PUBLIC_IP\",
    \"ttl\": 300,
    \"proxied\": true,
    \"comment\": \"R2R application on Azure VM\"
  }"

# Create CNAME for www (optional)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data "{
    \"type\": \"CNAME\",
    \"name\": \"www\",
    \"content\": \"$DOMAIN_NAME\",
    \"ttl\": 300,
    \"proxied\": true,
    \"comment\": \"WWW redirect for R2R\"
  }"
```

#### How to Get Cloudflare API Credentials:
1. **Get API Token**:
   - Go to Cloudflare Dashboard → **My Profile** → **API Tokens**
   - Click **Create Token**
   - Use **Custom token** template
   - **Permissions**: 
     - Zone:Zone:Read
     - Zone:DNS:Edit
   - **Zone Resources**: Include - All zones (or specific zone)
   - Click **Continue to summary** → **Create token**
   - **Copy and save the token**

2. **Get Zone ID**:
   - In Cloudflare Dashboard, select your domain
   - In the right sidebar, copy the **Zone ID**

### Step 5.3: Using Azure DNS (Alternative)
```bash
# Create DNS zone
az network dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name $DOMAIN

# Create A record
az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DOMAIN \
  --record-set-name "@" \
  --ipv4-address $PUBLIC_IP

# Create CNAME for www
az network dns record-set cname set-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DOMAIN \
  --record-set-name "www" \
  --cname $DOMAIN

# Get name servers (you'll need to update these with your domain registrar)
az network dns zone show \
  --resource-group $RESOURCE_GROUP \
  --name $DOMAIN \
  --query nameServers
```

### Step 5.4: Verify DNS Configuration
```bash
# Wait 5-10 minutes for DNS propagation, then test
nslookup $DOMAIN
dig $DOMAIN

# Test from different DNS servers
dig @8.8.8.8 $DOMAIN
dig @1.1.1.1 $DOMAIN

# Check if it resolves to your Azure IP
ping $DOMAIN
```

**DNS Propagation Notes:**
- DNS changes can take 5-60 minutes to propagate globally
- Cloudflare proxied records will show Cloudflare IPs, not your Azure IP
- Use `dig +trace your-domain.com` to see the full DNS resolution path

### Step 5.5: Manual Azure Portal Configuration (Alternative)

If you prefer using the Azure Portal instead of CLI commands, here are the manual steps:

#### Create Load Balancer via Azure Portal:
1. **Login to Azure Portal**
   - Go to [portal.azure.com](https://portal.azure.com)
   - Login with your Azure account

2. **Create Load Balancer**
   - Search for "Load balancers" → Click **Create**
   - **Resource group**: Select your resource group
   - **Name**: `r2r-lb`
   - **Region**: Same as your VMs
   - **SKU**: Standard
   - **Type**: Public
   - **Tier**: Regional
   - Click **Review + create** → **Create**

3. **Configure Load Balancer**
   - Go to your load balancer → **Frontend IP configuration**
   - Click **Add** → Create new public IP → Name: `r2r-public-ip`
   - Go to **Backend pools** → **Add** → Name: `r2r-backend`
   - Go to **Health probes** → **Add**:
     - Name: `r2r-health-probe`
     - Protocol: HTTP
     - Port: 80
     - Path: `/health`
   - Go to **Load balancing rules** → **Add**:
     - Name: `r2r-http-rule`
     - Frontend IP: Select your frontend IP
     - Protocol: TCP
     - Frontend port: 80
     - Backend port: 80
     - Backend pool: `r2r-backend`
     - Health probe: `r2r-health-probe`

#### Configure Network Security Group via Azure Portal:
1. **Create Network Security Group**
   - Search for "Network security groups" → **Create**
   - **Name**: `r2r-nsg`
   - **Resource group**: Select your resource group
   - Click **Review + create** → **Create**

2. **Add Security Rules**
   - Go to your NSG → **Inbound security rules**
   - Click **Add** for each rule:
     - **SSH**: Source: Any, Port: 22, Protocol: TCP, Action: Allow, Priority: 1000
     - **HTTP**: Source: Any, Port: 80, Protocol: TCP, Action: Allow, Priority: 1001
     - **HTTPS**: Source: Any, Port: 443, Protocol: TCP, Action: Allow, Priority: 1002

#### Create VM Scale Set via Azure Portal:
1. **Create Virtual Machine Scale Set**
   - Search for "Virtual machine scale sets" → **Create**
   - **Resource group**: Select your resource group
   - **Name**: `r2r-vmss`
   - **Region**: Same as other resources
   - **Image**: Ubuntu Server 22.04 LTS
   - **Size**: Standard_B2s (or preferred size)
   - **Authentication**: SSH public key
   - **Username**: `azureuser`

2. **Configure Networking**
   - **Virtual network**: Create new or select existing
   - **Load balancer**: Select `r2r-lb`
   - **Network security group**: Select `r2r-nsg`

3. **Configure Scaling**
   - **Initial instance count**: 2
   - **Scaling policy**: Custom
   - **Minimum instances**: 2
   - **Maximum instances**: 5
   - **Scale out**: CPU > 70%
   - **Scale in**: CPU < 30%

## 📊 Phase 6: Monitoring and Maintenance

### Step 6.1: Setup Application Insights
```bash
# Create Application Insights
az monitor app-insights component create \
  --resource-group $RESOURCE_GROUP \
  --app r2r-insights \
  --location $LOCATION \
  --kind web

# Get instrumentation key
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --resource-group $RESOURCE_GROUP \
  --app r2r-insights \
  --query instrumentationKey \
  --output tsv)

echo "Add this to your environment: APPINSIGHTS_INSTRUMENTATIONKEY=$INSTRUMENTATION_KEY"
```

### Step 6.2: Setup Log Analytics
```bash
# Create Log Analytics workspace
az monitor log-analytics workspace create \
  --resource-group $RESOURCE_GROUP \
  --workspace-name r2r-logs \
  --location $LOCATION

# Create monitoring dashboard
az portal dashboard create \
  --resource-group $RESOURCE_GROUP \
  --name r2r-dashboard \
  --input-path dashboard.json
```

### Step 6.3: Health Monitoring Script
```bash
# Create health monitoring script
cat > health-monitor.sh << 'EOF'
#!/bin/bash

DOMAIN="your-domain.com"
HEALTH_URL="https://$DOMAIN/v3/health"

while true; do
    response=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_URL)
    if [ $response -eq 200 ]; then
        echo "$(date): Service is healthy"
    else
        echo "$(date): Service is unhealthy (HTTP $response)"
        # Add alerting logic here
    fi
    sleep 30
done
EOF

chmod +x health-monitor.sh
```

## ✅ Phase 7: Verification and Testing

### Step 7.1: Test Application
```bash
# Test health endpoint
curl https://your-domain.com/v3/health

# Test API
curl -X GET https://your-domain.com/v3/system/health

# Test dashboard
curl -I https://your-domain.com/
```

### Step 7.2: Load Testing
```bash
# Install Apache Bench
sudo apt install apache2-utils

# Run load test
ab -n 1000 -c 10 https://your-domain.com/v3/health
```

### Step 7.3: SSL Testing
```bash
# Test SSL configuration
curl -I https://your-domain.com/
openssl s_client -connect your-domain.com:443 -servername your-domain.com
```

## 🔄 Phase 8: Backup and Disaster Recovery

### Step 8.1: Database Backup
```bash
# Create backup script
cat > backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/var/backups/r2r"

mkdir -p $BACKUP_DIR

# Backup PostgreSQL
docker exec postgres pg_dump -U postgres r2r > $BACKUP_DIR/r2r_$DATE.sql

# Backup MinIO data
docker exec minio mc mirror /data $BACKUP_DIR/minio_$DATE/

# Upload to Azure Storage (optional)
# az storage blob upload-batch --destination backups --source $BACKUP_DIR
EOF

chmod +x backup.sh
```

### Step 8.2: Automated Backup Schedule
```bash
# Add to crontab
crontab -e
# Add this line for daily backups at 2 AM
# 0 2 * * * /home/azureuser/R2R/docker/backup.sh
```

## 🎉 Success! Your R2R Production Deployment is Complete

### What You've Built:
- ✅ Production R2R application on Azure VM Scale Set
- ✅ Auto-scaling based on CPU usage (2-5 instances)
- ✅ Load balancer with health checks
- ✅ SSL certificate with automatic renewal
- ✅ DNS configuration with your custom domain
- ✅ Monitoring and logging
- ✅ Backup and disaster recovery
- ✅ Security best practices

### Your URLs:
- **Main App**: https://your-domain.com
- **API Documentation**: https://your-domain.com/v3/docs
- **Health Check**: https://your-domain.com/v3/health

### Maintenance Commands:
```bash
# Check service status
docker-compose -f docker-compose.prod.yaml ps

# View logs
docker-compose -f docker-compose.prod.yaml logs -f r2r

# Update application
docker-compose -f docker-compose.prod.yaml pull
docker-compose -f docker-compose.prod.yaml up -d

# Scale manually
az vmss scale --resource-group $RESOURCE_GROUP --name r2r-vmss --new-capacity 3
```

## 💰 Cost Optimization

### Estimated Monthly Costs:
- **VM Scale Set**: $100-300/month (depending on instance size/count)
- **Load Balancer**: $25/month
- **Public IP**: $4/month
- **Storage**: $20-50/month
- **Monitoring**: $10-30/month
- **Total**: ~$160-400/month

### Cost Saving Tips:
1. Use **Spot Instances** for non-critical workloads (50-90% savings)
2. Enable **Auto-shutdown** for development environments
3. Use **Reserved Instances** for predictable workloads (40-60% savings)
4. Monitor and optimize resource usage regularly

## 🆘 Troubleshooting

### Common Issues:

#### Application Won't Start
```bash
# Check logs
docker-compose -f docker-compose.prod.yaml logs r2r

# Check environment variables
docker-compose -f docker-compose.prod.yaml exec r2r env
```

#### SSL Certificate Issues
```bash
# Renew certificate
sudo docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot renew

# Restart nginx
docker-compose -f docker-compose.prod.yaml restart nginx
```

#### Load Balancer Health Check Failing
```bash
# Check health endpoint
curl http://localhost/health

# Check nginx logs
docker-compose -f docker-compose.prod.yaml logs nginx
```

#### Database Connection Issues
```bash
# Check PostgreSQL
docker-compose -f docker-compose.prod.yaml exec postgres psql -U postgres -c '\l'

# Check connectivity
docker-compose -f docker-compose.prod.yaml exec r2r ping postgres
```

---

**🎊 Congratulations!** You've successfully deployed R2R on Azure with enterprise-grade infrastructure, SSL, auto-scaling, and monitoring. Your application is now ready for production workloads.