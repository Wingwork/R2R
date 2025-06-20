# Generate Kubernetes ConfigMap with PostgreSQL configuration
resource "local_file" "azure_configmap" {
  content = templatefile("${path.module}/../kubernetes/azure-overlay/azure-configmap.yaml", {
    postgres_host     = var.postgres_config.host
    postgres_port     = var.postgres_config.port
    postgres_username = var.postgres_config.username
    postgres_database = var.postgres_config.database
  })
  filename = "${path.module}/../kubernetes/azure-overlay/azure-configmap-generated.yaml"
}

# Generate Kubernetes Secret with PostgreSQL password
resource "local_file" "postgres_secret" {
  content = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "postgres-credentials"
      namespace = "ai-system"
      labels = {
        app       = "r2r"
        component = "database"
        provider  = "external"
      }
    }
    type = "Opaque"
    stringData = {
      R2R_POSTGRES_PASSWORD = var.postgres_config.password
      POSTGRES_URL         = "postgresql://${var.postgres_config.username}:${var.postgres_config.password}@${var.postgres_config.host}:${var.postgres_config.port}/${var.postgres_config.database}"
    }
  })
  filename = "${path.module}/../kubernetes/azure-overlay/postgres-secret-generated.yaml"
}