# Core Configuration Variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "application_name" {
  description = "Name of the application"
  type        = string
  default     = "r2r"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-r2r-prod"
}

# Common Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment   = "prod"
    Application   = "r2r"
    ManagedBy    = "terraform"
    Owner        = "platform-team"
    CostCenter   = "engineering"
    Project      = "r2r-deployment"
  }
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "appgw_subnet_address_prefix" {
  description = "Address prefix for Application Gateway subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "service_cidr" {
  description = "CIDR block for Kubernetes services"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.1.0.10"
}

# AKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28.3"
}

variable "enable_private_cluster" {
  description = "Enable private AKS cluster (recommended for production)"
  type        = bool
  default     = false  # Set to true for production with proper network setup
}

variable "aks_admin_group_object_ids" {
  description = "Azure AD group object IDs for AKS administrators"
  type        = list(string)
  default     = []
  # To find your group ID: az ad group show --group "your-group-name" --query objectId -o tsv
}

# Node Pool Configuration
variable "default_node_pool" {
  description = "Configuration for default node pool"
  type = object({
    node_count = number
    vm_size    = string
    min_count  = number
    max_count  = number
  })
  default = {
    node_count = 3
    vm_size    = "Standard_D2s_v3"  # 2 vCPU, 8GB RAM
    min_count  = 2
    max_count  = 10
  }
}

variable "app_node_pool" {
  description = "Configuration for application node pool"
  type = object({
    node_count = number
    vm_size    = string
    min_count  = number
    max_count  = number
  })
  default = {
    node_count = 2
    vm_size    = "Standard_D4s_v3"  # 4 vCPU, 16GB RAM - better for R2R workloads
    min_count  = 1
    max_count  = 8
  }
}

# Container Registry Configuration
variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = can(regex("^(Basic|Standard|Premium)$", var.acr_sku))
    error_message = "ACR SKU must be one of: Basic, Standard, Premium."
  }
}

# Application Gateway Configuration
variable "enable_application_gateway" {
  description = "Enable Application Gateway for advanced routing and SSL termination"
  type        = bool
  default     = false  # Set to true if you need advanced routing features
}

# Storage Configuration
variable "postgres_disk_size_gb" {
  description = "Disk size in GB for PostgreSQL storage"
  type        = number
  default     = 100
  
  validation {
    condition     = var.postgres_disk_size_gb >= 32 && var.postgres_disk_size_gb <= 32767
    error_message = "PostgreSQL disk size must be between 32 and 32767 GB."
  }
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for the application (e.g., r2r.wingwork.com)"
  type        = string
  default     = "r2r.wingwork.com"
}

# SSL/TLS Configuration
variable "enable_ssl" {
  description = "Enable SSL/TLS certificates"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring stack"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 7 && var.log_retention_days <= 730
    error_message = "Log retention must be between 7 and 730 days."
  }
}

# R2R Application Configuration
variable "r2r_config" {
  description = "R2R application configuration"
  type = object({
    replicas                = number
    cpu_request            = string
    memory_request         = string
    cpu_limit              = string
    memory_limit           = string
    postgres_storage_size  = string
    redis_storage_size     = string
  })
  default = {
    replicas               = 3
    cpu_request           = "500m"
    memory_request        = "1Gi"
    cpu_limit             = "2000m"
    memory_limit          = "4Gi"
    postgres_storage_size = "50Gi"
    redis_storage_size    = "10Gi"
  }
}

# Security Configuration
variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policy"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Kubernetes Network Policies"
  type        = bool
  default     = true
}

# Backup Configuration
variable "backup_configuration" {
  description = "Backup configuration settings"
  type = object({
    enabled                = bool
    retention_days        = number
    backup_frequency_hours = number
  })
  default = {
    enabled                = true
    retention_days        = 30
    backup_frequency_hours = 24
  }
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

variable "auto_shutdown_schedule" {
  description = "Auto shutdown schedule for development environments"
  type = object({
    enabled   = bool
    time      = string
    timezone  = string
  })
  default = {
    enabled  = false
    time     = "19:00"
    timezone = "UTC"
  }
}

# External Integrations
variable "cloudflare_config" {
  description = "Cloudflare configuration for DNS and CDN"
  type = object({
    zone_id     = string
    api_token   = string
    enable_cdn  = bool
    enable_waf  = bool
  })
  default = {
    zone_id    = ""
    api_token  = ""
    enable_cdn = true
    enable_waf = true
  }
  sensitive = true
}

# API Keys and Secrets (these should be provided via environment variables or tfvars file)
variable "api_keys" {
  description = "API keys for external services"
  type = object({
    openai_api_key      = string
    anthropic_api_key   = string
    azure_api_key       = string
    google_api_key      = string
    github_client_id    = string
    github_client_secret = string
  })
  default = {
    openai_api_key       = ""
    anthropic_api_key    = ""
    azure_api_key        = ""
    google_api_key       = ""
    github_client_id     = ""
    github_client_secret = ""
  }
  sensitive = true
}

# Database Configuration
variable "postgres_config" {
  description = "PostgreSQL configuration"
  type = object({
    version              = string
    instance_class       = string
    allocated_storage    = number
    max_allocated_storage = number
    backup_retention_period = number
    multi_az            = bool
    storage_encrypted   = bool
  })
  default = {
    version                 = "16"
    instance_class         = "Standard_D2s_v3"
    allocated_storage      = 100
    max_allocated_storage  = 500
    backup_retention_period = 7
    multi_az               = true
    storage_encrypted      = true
  }
}

# Alert Configuration
variable "alert_configuration" {
  description = "Monitoring and alerting configuration"
  type = object({
    slack_webhook_url     = string
    email_recipients      = list(string)
    pagerduty_service_key = string
    enable_slack_alerts   = bool
    enable_email_alerts   = bool
    enable_pagerduty      = bool
  })
  default = {
    slack_webhook_url     = ""
    email_recipients      = []
    pagerduty_service_key = ""
    enable_slack_alerts   = false
    enable_email_alerts   = true
    enable_pagerduty      = false
  }
  sensitive = true
}