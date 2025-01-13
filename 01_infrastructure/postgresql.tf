resource "random_password" "postgresql_password" {
  length  = 16
  special = false
}

resource "helm_release" "postgresql" {
  name       = "postgresql"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "postgresql"
  version    = "16.4.2"
  namespace  = var.dependencies_namespace

  create_namespace = true

  set {
    name  = "global.postgresql.auth.username"
    value = var.gcp_platform_name
  }

  set {
    name  = "global.postgresql.auth.password"
    value = random_password.postgresql_password.result
  }

  set {
    name  = "global.postgresql.auth.postgresPassword"
    value = random_password.postgresql_password.result
  }

  set {
    name  = "global.postgresql.auth.database"
    value = var.gcp_platform_name
  }

  depends_on = [module.gke, kubernetes_namespace.cluster_dependencies_namespace]
}