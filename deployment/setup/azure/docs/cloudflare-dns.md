# Cloudflare DNS Configuration for R2R on Azure

This guide covers configuring Cloudflare DNS to point `r2r.wingwork.com` to your Azure Kubernetes Service deployment with SSL/TLS certificates.

## 📋 Prerequisites

1. **Domain registered** and managed through Cloudflare
2. **R2R deployed** on Azure AKS with external access
3. **Azure Load Balancer** with public IP assigned
4. **Cloudflare account** with API access

## 🌐 Overview

The DNS setup involves:
1. **Azure Load Balancer** → Public IP for AKS ingress
2. **Cloudflare DNS** → Points `r2r.wingwork.com` to Azure public IP
3. **SSL/TLS Certificates** → Automatic via cert-manager + Let's Encrypt
4. **CDN & Security** → Cloudflare proxy for performance and protection

## 🚀 Quick Start

### 1. Get Azure Public IP
```bash
# Get the public IP from Terraform
cd deployment/setup/azure/terraform
AZURE_PUBLIC_IP=$(terraform output -raw public_ip_address)
echo "Azure Public IP: $AZURE_PUBLIC_IP"

# Or get from Azure CLI
az network public-ip show \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw public_ip_address | cut -d'/' -f9) \
  --query ipAddress -o tsv
```

### 2. Configure Cloudflare DNS
```bash
# Using Cloudflare API (replace with your values)
CLOUDFLARE_API_TOKEN="your-api-token"
ZONE_ID="your-zone-id"
AZURE_IP="your-azure-public-ip"

# Create A record for r2r.wingwork.com
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "r2r",
    "content": "'$AZURE_IP'",
    "ttl": 300,
    "proxied": true
  }'
```

### 3. Verify DNS Resolution
```bash
# Test DNS resolution
nslookup r2r.wingwork.com
dig r2r.wingwork.com

# Test HTTP connectivity (may show SSL error initially)
curl -I http://r2r.wingwork.com
```

### 4. Configure SSL Certificate
```bash
# SSL certificate will be automatically provisioned by cert-manager
# Check certificate status
kubectl get certificates -n ai-system
kubectl describe certificate r2r-tls -n ai-system

# Check Let's Encrypt challenge
kubectl get challenges -n ai-system
```

## 📁 Configuration Files

### Cloudflare Zone Configuration
Create a configuration file for managing Cloudflare settings:

```bash
# Create cloudflare-config.yaml
cat > cloudflare-config.yaml << EOF
zone_id: "your-zone-id"
zone_name: "wingwork.com"
records:
  - name: "r2r"
    type: "A"
    content: "$AZURE_PUBLIC_IP"
    ttl: 300
    proxied: true
  - name: "*.r2r"
    type: "CNAME"
    content: "r2r.wingwork.com"
    ttl: 300
    proxied: true
security:
  ssl_mode: "Full (strict)"
  always_use_https: true
  min_tls_version: "1.2"
  http_strict_transport_security:
    enabled: true
    max_age: 31536000
    include_subdomains: true
performance:
  caching_level: "aggressive"
  browser_cache_ttl: 14400
  edge_cache_ttl: 7200
EOF
```

## ⚙️ Step-by-Step Configuration

### Step 1: Cloudflare API Setup

#### Get API Token
1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Go to **My Profile** → **API Tokens**
3. Create token with permissions:
   - Zone:Zone:Read
   - Zone:DNS:Edit
   - Zone:Zone Settings:Edit

#### Get Zone ID
```bash
# Get zone ID for wingwork.com
curl -X GET "https://api.cloudflare.com/client/v4/zones?name=wingwork.com" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r '.result[0].id'
```

### Step 2: DNS Record Configuration

#### Create A Record
```bash
# Create main A record
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "A",
    "name": "r2r",
    "content": "'$AZURE_IP'",
    "ttl": 300,
    "proxied": true,
    "comment": "R2R application on Azure AKS"
  }'
```

#### Create CNAME for Subdomains (Optional)
```bash
# Create wildcard CNAME for subdomains
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "type": "CNAME",
    "name": "*.r2r",
    "content": "r2r.wingwork.com",
    "ttl": 300,
    "proxied": true,
    "comment": "Wildcard for R2R subdomains"
  }'
```

#### Verify DNS Records
```bash
# List all DNS records for the zone
curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" | \
  jq '.result[] | select(.name | contains("r2r"))'
```

### Step 3: SSL/TLS Configuration

#### Configure SSL Mode
```bash
# Set SSL mode to Full (strict)
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": "strict"}'

# Enable Always Use HTTPS
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/always_use_https" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": "on"}'

# Set minimum TLS version
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/min_tls_version" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": "1.2"}'
```

#### Enable HSTS
```bash
# Enable HTTP Strict Transport Security
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/security_header" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "value": {
      "strict_transport_security": {
        "enabled": true,
        "max_age": 31536000,
        "include_subdomains": true,
        "preload": true
      }
    }
  }'
```

### Step 4: Performance Optimization

#### Configure Caching
```bash
# Set caching level
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/cache_level" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": "aggressive"}'

# Set browser cache TTL
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/browser_cache_ttl" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"value": 14400}'
```

#### Page Rules for API Endpoints
```bash
# Create page rule for API endpoints (disable caching)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/pagerules" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "targets": [
      {
        "target": "url",
        "constraint": {
          "operator": "matches",
          "value": "r2r.wingwork.com/v3/*"
        }
      }
    ],
    "actions": [
      {
        "id": "cache_level",
        "value": "bypass"
      },
      {
        "id": "security_level",
        "value": "high"
      }
    ],
    "status": "active",
    "priority": 1
  }'
```

### Step 5: Security Configuration

#### Enable Security Features
```bash
# Enable Bot Fight Mode
curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/bot_management" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"fight_mode": true}'

# Configure rate limiting
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rate_limits" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "threshold": 100,
    "period": 60,
    "match": {
      "request": {
        "url": "r2r.wingwork.com/v3/*"
      }
    },
    "action": {
      "mode": "challenge"
    }
  }'
```

#### Firewall Rules
```bash
# Create firewall rule to allow specific countries only (optional)
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/firewall/rules" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{
    "filter": {
      "expression": "(http.host eq \"r2r.wingwork.com\") and (ip.geoip.country ne \"US\" and ip.geoip.country ne \"CA\" and ip.geoip.country ne \"GB\")"
    },
    "action": "challenge",
    "description": "Challenge non-US/CA/GB traffic to R2R"
  }'
```

## 🔍 Verification and Testing

### DNS Verification
```bash
# Test DNS resolution
dig r2r.wingwork.com A
dig r2r.wingwork.com AAAA

# Test from different locations
nslookup r2r.wingwork.com 8.8.8.8
nslookup r2r.wingwork.com 1.1.1.1

# Check DNS propagation globally
# Visit: https://dnschecker.org/#A/r2r.wingwork.com
```

### SSL Certificate Verification
```bash
# Check SSL certificate
echo | openssl s_client -connect r2r.wingwork.com:443 -servername r2r.wingwork.com

# Test SSL with curl
curl -I https://r2r.wingwork.com/v3/health

# Check certificate details
echo | openssl s_client -connect r2r.wingwork.com:443 2>/dev/null | openssl x509 -noout -text
```

### Application Testing
```bash
# Test main application
curl -s https://r2r.wingwork.com/v3/health | jq .

# Test with different user agents
curl -H "User-Agent: Mozilla/5.0" https://r2r.wingwork.com/v3/health

# Test API endpoints
curl -X POST https://r2r.wingwork.com/v3/documents \
  -H "Content-Type: application/json" \
  -d '{"text": "test document"}'
```

### Performance Testing
```bash
# Test response times
curl -w "@curl-format.txt" -o /dev/null -s https://r2r.wingwork.com/v3/health

# Where curl-format.txt contains:
#     time_namelookup:  %{time_namelookup}\n
#        time_connect:  %{time_connect}\n
#     time_appconnect:  %{time_appconnect}\n
#    time_pretransfer:  %{time_pretransfer}\n
#       time_redirect:  %{time_redirect}\n
#  time_starttransfer:  %{time_starttransfer}\n
#                     ----------\n
#          time_total:  %{time_total}\n

# Load testing (use with caution)
# ab -n 100 -c 10 https://r2r.wingwork.com/v3/health
```

## 🛠️ Management Scripts

### Cloudflare Management Script
```bash
#!/bin/bash
# cloudflare-manage.sh - Manage Cloudflare DNS for R2R

CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}"
ZONE_ID="${CLOUDFLARE_ZONE_ID}"
DOMAIN="r2r.wingwork.com"

function get_azure_ip() {
    cd deployment/setup/azure/terraform
    terraform output -raw public_ip_address
}

function update_dns_record() {
    local new_ip=$(get_azure_ip)
    local record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | \
        jq -r '.result[0].id')
    
    curl -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"r2r\",\"content\":\"$new_ip\",\"ttl\":300,\"proxied\":true}"
}

function purge_cache() {
    curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/purge_cache" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"purge_everything":true}'
}

case "$1" in
    update-ip)
        update_dns_record
        ;;
    purge-cache)
        purge_cache
        ;;
    status)
        curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq '.result[]'
        ;;
    *)
        echo "Usage: $0 {update-ip|purge-cache|status}"
        exit 1
        ;;
esac
```

## 🚨 Troubleshooting

### Common Issues

#### DNS Not Resolving
```bash
# Check if DNS record exists
dig r2r.wingwork.com

# Check Cloudflare configuration
curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=r2r" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"

# Force DNS flush
sudo dscacheutil -flushcache  # macOS
sudo systemctl flush-dns     # Linux
ipconfig /flushdns           # Windows
```

#### SSL Certificate Issues
```bash
# Check cert-manager status
kubectl get certificates -n ai-system
kubectl describe certificate r2r-tls -n ai-system
kubectl get challenges -n ai-system

# Check Let's Encrypt ACME challenge
kubectl logs -f deployment/cert-manager -n cert-manager

# Manual certificate request
kubectl delete certificate r2r-tls -n ai-system
kubectl apply -f ../kubernetes/ingress/ssl-certificates.yaml
```

#### Cloudflare 522 Errors
```bash
# Check if Azure Load Balancer is responding
curl -I http://$AZURE_PUBLIC_IP

# Check Kubernetes ingress
kubectl get ingress -n ai-system
kubectl describe ingress r2r-ingress -n ai-system

# Check service endpoints
kubectl get endpoints -n ai-system
```

#### Performance Issues
```bash
# Disable Cloudflare proxy temporarily
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  --data '{"proxied": false}'

# Check origin server directly
curl -H "Host: r2r.wingwork.com" http://$AZURE_PUBLIC_IP/v3/health

# Re-enable proxy
curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  --data '{"proxied": true}'
```

### Recovery Procedures

#### DNS Rollback
```bash
# Update DNS to point to old infrastructure
OLD_IP="previous-ip-address"
./cloudflare-manage.sh update-ip $OLD_IP
```

#### SSL Certificate Reset
```bash
# Delete and recreate certificate
kubectl delete certificate r2r-tls -n ai-system
kubectl delete secret r2r-tls -n ai-system
kubectl apply -f ../kubernetes/ingress/ssl-certificates.yaml
```

## 📚 Additional Resources

- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Cloudflare SSL/TLS Options](https://developers.cloudflare.com/ssl/)

## 🆘 Support

For DNS and SSL issues:
1. Check Cloudflare dashboard for any service issues
2. Verify DNS propagation using online tools
3. Test SSL certificate validity
4. Check Azure Load Balancer health
5. Review cert-manager logs for certificate issues

---

**Next Step**: After DNS configuration, proceed to [Application Testing and Monitoring](monitoring.md)