# AKS Cluster Outputs
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_cluster_private_fqdn" {
  description = "Private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.private_fqdn
}

output "aks_node_resource_group" {
  description = "Resource group containing the AKS nodes"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

# Network Outputs
output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "appgw_subnet_id" {
  description = "ID of the Application Gateway subnet"
  value       = azurerm_subnet.appgw.id
}

# Container Registry Outputs
output "acr_login_server" {
  description = "Login server for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

# Key Vault Outputs
output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

# Public IP Outputs
output "public_ip_address" {
  description = "Public IP address for load balancer"
  value       = azurerm_public_ip.main.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the public IP"
  value       = azurerm_public_ip.main.fqdn
}

# Application Gateway Outputs (if enabled)
output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = var.enable_application_gateway ? azurerm_application_gateway.main[0].id : null
}

output "application_gateway_public_ip" {
  description = "Public IP of the Application Gateway"
  value       = var.enable_application_gateway ? azurerm_public_ip.main.ip_address : null
}

# Log Analytics Workspace Outputs
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

# Storage Account Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Identity Outputs
output "aks_identity_principal_id" {
  description = "Principal ID of the AKS managed identity"
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "aks_identity_tenant_id" {
  description = "Tenant ID of the AKS managed identity"
  value       = azurerm_kubernetes_cluster.main.identity[0].tenant_id
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# Kubernetes Configuration Outputs
output "kube_config" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kubernetes_cluster_ca_certificate" {
  description = "CA certificate for the Kubernetes cluster"
  value       = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  sensitive   = true
}

output "kubernetes_host" {
  description = "Kubernetes API server host"
  value       = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive   = true
}

# Connection Information
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "acr_login_command" {
  description = "Command to login to Azure Container Registry"
  value       = "az acr login --name ${azurerm_container_registry.main.name}"
}

# Application URLs (for post-deployment)
output "application_urls" {
  description = "URLs for accessing the deployed application"
  value = {
    r2r_api        = "https://${var.domain_name}/api"
    r2r_dashboard  = "https://${var.domain_name}"
    grafana        = "https://${var.domain_name}/grafana"
    prometheus     = "https://${var.domain_name}/prometheus"
  }
}

# Monitoring and Logging
output "monitoring_endpoints" {
  description = "Monitoring and logging endpoints"
  value = {
    log_analytics_workspace = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_log_analytics_workspace.main.id}"
    azure_monitor          = "https://portal.azure.com/#@${data.azurerm_client_config.current.tenant_id}/resource${azurerm_kubernetes_cluster.main.id}/overview"
  }
}

# Security Information
output "security_information" {
  description = "Security-related information and endpoints"
  value = {
    key_vault_url    = azurerm_key_vault.main.vault_uri
    private_cluster  = var.enable_private_cluster
    network_policy   = "azure"
    rbac_enabled     = true
  }
}

# Cost Tracking Tags
output "resource_tags" {
  description = "Common tags applied to resources for cost tracking"
  value       = var.common_tags
}

# Network Configuration Summary
output "network_configuration" {
  description = "Network configuration summary"
  value = {
    vnet_address_space       = var.vnet_address_space
    aks_subnet_cidr         = var.aks_subnet_address_prefix
    appgw_subnet_cidr       = var.appgw_subnet_address_prefix
    service_cidr            = var.service_cidr
    dns_service_ip          = var.dns_service_ip
  }
}

# Node Pool Configuration
output "node_pool_configuration" {
  description = "Node pool configuration summary"
  value = {
    default_node_pool = {
      vm_size    = var.default_node_pool.vm_size
      node_count = var.default_node_pool.node_count
      min_count  = var.default_node_pool.min_count
      max_count  = var.default_node_pool.max_count
    }
    app_node_pool = {
      vm_size    = var.app_node_pool.vm_size
      node_count = var.app_node_pool.node_count
      min_count  = var.app_node_pool.min_count
      max_count  = var.app_node_pool.max_count
    }
  }
}