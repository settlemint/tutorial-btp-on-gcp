resource "random_password" "redis_password" {
  length  = 16
  special = false
}

resource "helm_release" "redis" {
  name       = "redis"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "redis"
  version    = "20.12.0"
  namespace  = var.dependencies_namespace

  create_namespace = true

  set {
    name  = "architecture"
    value = "standalone"
  }

  set {
    name  = "global.redis.password"
    value = random_password.redis_password.result
  }

  depends_on = [module.gke, kubernetes_namespace.cluster_dependencies_namespace]
}