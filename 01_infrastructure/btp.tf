resource "random_password" "jwtSigningKey" {
  length  = 32
  special = false
}

resource "random_password" "encryption_key" {
  length  = 16
  special = false
}

resource "random_password" "grafana_password" {
  length  = 16
  special = false
}

locals {
  values_yaml = templatefile("${path.module}/values.yaml.tmpl", {
    gcp_dns_zone                   = var.gcp_dns_zone
    dependencies_namespace         = var.dependencies_namespace
    redis_password                 = random_password.redis_password.result
    gcp_platform_name              = var.gcp_platform_name
    postgresql_password            = random_password.postgresql_password.result
    jwtSigningKey                  = random_password.jwtSigningKey.result
    gcp_client_id                  = var.gcp_client_id
    gcp_client_secret              = var.gcp_client_secret
    role_id                        = local.role_id
    secret_id                      = local.secret_id
    gcp_region                     = var.gcp_region
    encryption_key                 = random_password.encryption_key.result
    minio_svcacct_access_key       = random_password.minio_svcacct_access_key.result
    minio_svcacct_secret_key       = random_password.minio_svcacct_secret_key.result
    deployment_namespace           = var.deployment_namespace
    grafana_password               = random_password.grafana_password.result
    external_dns_workload_identity = var.external_dns_workload_identity
    gcp_project_id                 = var.gcp_project_id
  })
}

resource "helm_release" "settlemint" {
  name             = "settlemint"
  repository       = "oci://registry.settlemint.com/settlemint-platform"
  chart            = "settlemint"
  namespace        = "settlemint"
  version          = var.btp_version
  create_namespace = true

  values = [local.values_yaml]

  depends_on = [kubernetes_job.vault_unseal]
}