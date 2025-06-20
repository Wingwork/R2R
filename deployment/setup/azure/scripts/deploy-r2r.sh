#!/bin/bash

# ===================================================================
# R2R Azure Deployment Script
# ===================================================================
# This script automates the deployment of R2R on Azure Kubernetes Service
# 
# Usage: ./deploy-r2r.sh [OPTIONS]
# Options:
#   --phase <phase>     Deploy specific phase: infrastructure|kubernetes|monitoring|dns
#   --env <environment> Environment: dev|staging|prod (default: prod)
#   --dry-run          Show what would be done without executing
#   --skip-deps        Skip dependency checks
#   --help             Show this help message
#
# Prerequisites:
#   - Azure CLI installed and authenticated
#   - Terraform >= 1.6 installed
#   - kubectl installed
#   - Helm 3.x installed
#   - Domain configured in Cloudflare
# ===================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
AZURE_DIR="$PROJECT_ROOT/deployment/setup/azure"

# Default values
ENVIRONMENT="prod"
PHASE="all"
DRY_RUN=false
SKIP_DEPS=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_step() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

# Help function
show_help() {
    cat << EOF
R2R Azure Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --phase <phase>     Deploy specific phase:
                        - infrastructure: Deploy Azure resources with Terraform
                        - kubernetes: Deploy R2R application to AKS
                        - monitoring: Deploy Prometheus/Grafana
                        - dns: Configure Cloudflare DNS
                        - all: Deploy everything (default)
    
    --env <environment> Environment to deploy:
                        - dev: Development environment
                        - staging: Staging environment  
                        - prod: Production environment (default)
    
    --dry-run          Show what would be done without executing
    --skip-deps        Skip dependency checks
    --verbose          Enable verbose output
    --help             Show this help message

EXAMPLES:
    $0                                    # Deploy everything to production
    $0 --phase infrastructure            # Deploy only infrastructure
    $0 --env dev --phase kubernetes      # Deploy app to dev environment
    $0 --dry-run                         # Preview what would be deployed

PREREQUISITES:
    - Azure CLI installed and authenticated
    - Terraform >= 1.6 installed
    - kubectl installed
    - Helm 3.x installed
    - Cloudflare API token configured
    - Domain managed by Cloudflare

For detailed documentation, see: deployment/setup/azure/README.md
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --phase)
                PHASE="$2"
                shift 2
                ;;
            --env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done

    # Validate phase
    case $PHASE in
        infrastructure|kubernetes|monitoring|dns|all)
            ;;
        *)
            log_error "Invalid phase: $PHASE. Must be one of: infrastructure, kubernetes, monitoring, dns, all"
            ;;
    esac

    # Validate environment
    case $ENVIRONMENT in
        dev|staging|prod)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        log_warning "Skipping dependency checks"
        return
    fi

    log_step "Checking Dependencies"

    # Check if running in correct directory
    if [[ ! -d "$PROJECT_ROOT/deployment/k8s" ]]; then
        log_error "Must run from R2R project root. Current dir: $(pwd)"
    fi

    # Check required commands
    local deps=("az" "terraform" "kubectl" "helm" "jq" "curl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "$dep is required but not installed"
        fi
    done

    # Check Azure authentication
    if ! az account show &> /dev/null; then
        log_error "Azure CLI not authenticated. Run: az login"
    fi

    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    local required_version="1.6.0"
    if ! printf '%s\n%s\n' "$required_version" "$tf_version" | sort -V -C; then
        log_error "Terraform version $tf_version is too old. Required: >= $required_version"
    fi

    # Check if terraform.tfvars exists
    if [[ ! -f "$AZURE_DIR/terraform/terraform.tfvars" ]]; then
        log_error "terraform.tfvars not found. Copy from terraform.tfvars.example and configure"
    fi

    log_success "All dependencies satisfied"
}

# Infrastructure deployment
deploy_infrastructure() {
    log_step "Deploying Infrastructure with Terraform"
    
    cd "$AZURE_DIR/terraform"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run terraform plan"
        return
    fi

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init

    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate

    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -var="environment=$ENVIRONMENT" -out=tfplan

    # Apply deployment
    log_info "Applying Terraform deployment..."
    read -p "Continue with Terraform apply? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        log_success "Infrastructure deployed successfully"
    else
        log_warning "Terraform apply cancelled"
        exit 1
    fi

    # Configure kubectl
    log_info "Configuring kubectl..."
    local rg_name=$(terraform output -raw resource_group_name)
    local cluster_name=$(terraform output -raw aks_cluster_name)
    az aks get-credentials --resource-group "$rg_name" --name "$cluster_name" --overwrite-existing

    log_success "Infrastructure deployment complete"
}

# Kubernetes deployment  
deploy_kubernetes() {
    log_step "Deploying R2R Application to Kubernetes"

    # Verify cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check kubectl configuration"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy to Kubernetes"
        kubectl apply --dry-run=client -k "$AZURE_DIR/kubernetes/azure-overlay/"
        return
    fi

    # Check if secrets are configured
    if [[ ! -f "$AZURE_DIR/kubernetes/azure-overlay/azure-secrets.yaml" ]]; then
        log_error "azure-secrets.yaml not found. Copy from azure-secrets.yaml.example and configure"
    fi

    # Deploy base infrastructure components
    log_info "Installing NGINX Ingress Controller..."
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    
    if ! helm list -n ingress-nginx | grep -q ingress-nginx; then
        helm install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --values "$AZURE_DIR/kubernetes/values/ingress-nginx.yaml" \
            --wait --timeout=10m
    fi

    # Deploy cert-manager
    log_info "Installing cert-manager..."
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    
    if ! helm list -n cert-manager | grep -q cert-manager; then
        helm install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --values "$AZURE_DIR/kubernetes/values/cert-manager.yaml" \
            --wait --timeout=10m
    fi

    # Deploy R2R application using existing kustomization with Azure overlay
    log_info "Deploying R2R application..."
    kubectl apply -k "$AZURE_DIR/kubernetes/azure-overlay/"

    # Wait for deployments to be ready
    log_info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment --all -n ai-system

    # Deploy ingress
    log_info "Configuring ingress..."
    kubectl apply -f "$AZURE_DIR/kubernetes/ingress.yaml"

    log_success "Kubernetes deployment complete"
}

# Monitoring deployment
deploy_monitoring() {
    log_step "Deploying Monitoring Stack"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy monitoring"
        return
    fi

    # Add Prometheus Helm repository
    log_info "Adding Prometheus Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # Deploy Prometheus stack
    log_info "Installing Prometheus monitoring stack..."
    if ! helm list -n monitoring | grep -q prometheus; then
        helm install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --values "$AZURE_DIR/monitoring/prometheus-values.yaml" \
            --wait --timeout=15m
    fi

    # Get Grafana admin password
    local grafana_password=$(kubectl get secret prometheus-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode)
    log_success "Monitoring deployed. Grafana admin password: $grafana_password"
}

# DNS configuration
configure_dns() {
    log_step "Configuring Cloudflare DNS"

    # Get Azure public IP
    cd "$AZURE_DIR/terraform"
    local public_ip=$(terraform output -raw public_ip_address 2>/dev/null || echo "")
    
    if [[ -z "$public_ip" ]]; then
        log_error "Could not retrieve public IP from Terraform. Ensure infrastructure is deployed"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would configure DNS to point r2r.wingwork.com to $public_ip"
        return
    fi

    # Check for Cloudflare API token
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        log_error "CLOUDFLARE_API_TOKEN environment variable not set"
    fi

    if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
        log_error "CLOUDFLARE_ZONE_ID environment variable not set"
    fi

    log_info "Configuring DNS record for r2r.wingwork.com -> $public_ip"
    
    # Create or update DNS record
    local record_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=r2r.wingwork.com" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
    
    local record_id=$(echo "$record_response" | jq -r '.result[0].id // empty')
    
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
        # Update existing record
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"r2r\",\"content\":\"$public_ip\",\"ttl\":300,\"proxied\":true}" > /dev/null
    else
        # Create new record
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"r2r\",\"content\":\"$public_ip\",\"ttl\":300,\"proxied\":true}" > /dev/null
    fi

    log_success "DNS configured. r2r.wingwork.com now points to $public_ip"
}

# Verify deployment
verify_deployment() {
    log_step "Verifying Deployment"

    # Check infrastructure
    cd "$AZURE_DIR/terraform"
    if ! terraform show &> /dev/null; then
        log_error "Terraform state not found. Infrastructure may not be deployed"
    fi

    # Check Kubernetes
    if ! kubectl get pods -n ai-system &> /dev/null; then
        log_error "Cannot access ai-system namespace. Kubernetes deployment may have failed"
    fi

    # Check application health
    local retries=12
    local wait_time=10
    
    for ((i=1; i<=retries; i++)); do
        log_info "Checking application health (attempt $i/$retries)..."
        
        if curl -s --max-time 10 "https://r2r.wingwork.com/v3/health" > /dev/null 2>&1; then
            log_success "✅ Application is responding at https://r2r.wingwork.com"
            break
        elif [[ $i -eq $retries ]]; then
            log_warning "⚠️  Application not responding after $retries attempts"
            log_info "Check logs: kubectl logs -f deployment/r2r -n ai-system"
            break
        else
            log_info "Waiting ${wait_time}s before next attempt..."
            sleep $wait_time
        fi
    done

    # Show deployment summary
    log_step "Deployment Summary"
    echo "🌐 Application URL: https://r2r.wingwork.com"
    echo "📊 Grafana URL: https://r2r.wingwork.com/grafana"
    echo "🔍 Prometheus URL: https://r2r.wingwork.com/prometheus"
    echo "⚙️  Hatchet Dashboard: https://r2r.wingwork.com/hatchet"
    echo ""
    echo "📋 Useful Commands:"
    echo "  kubectl get pods -n ai-system"
    echo "  kubectl logs -f deployment/r2r -n ai-system"
    echo "  kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring"
    echo ""
    echo "📖 Documentation: deployment/setup/azure/README.md"
}

# Main execution
main() {
    log_info "Starting R2R Azure Deployment"
    log_info "Environment: $ENVIRONMENT"
    log_info "Phase: $PHASE"
    log_info "Dry Run: $DRY_RUN"

    # Check dependencies
    check_dependencies

    # Execute requested phase(s)
    case $PHASE in
        infrastructure)
            deploy_infrastructure
            ;;
        kubernetes)
            deploy_kubernetes
            ;;
        monitoring)
            deploy_monitoring
            ;;
        dns)
            configure_dns
            ;;
        all)
            deploy_infrastructure
            deploy_kubernetes
            deploy_monitoring
            configure_dns
            verify_deployment
            ;;
    esac

    log_success "Deployment phase '$PHASE' completed successfully!"
}

# Parse arguments and run main function
parse_args "$@"
main