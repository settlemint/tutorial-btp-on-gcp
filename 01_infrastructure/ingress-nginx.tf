resource "helm_release" "nginx_ingress" {
  name    = "ingress-nginx"
  version = "4.12.0"

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = var.dependencies_namespace

  set {
    name  = "controller.extraArgs.default-ssl-certificate"
    value = "${var.dependencies_namespace}/nginx-tls-secret"
  }

  create_namespace = true

  depends_on = [module.gke, kubernetes_namespace.cluster_dependencies_namespace]
}

data "kubernetes_service" "nginx_ingress" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = var.dependencies_namespace
  }

  depends_on = [helm_release.nginx_ingress]
}

data "google_dns_managed_zone" "dns_zone" {
  name    = var.gcp_platform_name
  project = var.gcp_project_id
}

resource "google_dns_record_set" "ingress_nginx_dns" {
  name         = "${var.gcp_dns_zone}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name

  rrdatas = [
    data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
  ]

  project = var.gcp_project_id

  depends_on = [data.kubernetes_service.nginx_ingress]
}

resource "google_dns_record_set" "wildcard_ingress_nginx_dns" {
  name         = "*.${var.gcp_dns_zone}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.dns_zone.name

  rrdatas = [
    data.kubernetes_service.nginx_ingress.status[0].load_balancer[0].ingress[0].ip
  ]

  project = var.gcp_project_id

  depends_on = [data.kubernetes_service.nginx_ingress]
}