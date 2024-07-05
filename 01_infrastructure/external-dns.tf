# resource "helm_release" "external_dns" {
#   name = "external-dns"

#   repository = "https://kubernetes-sigs.github.io/external-dns/"
#   chart      = "external-dns"
#   version    = "1.14.5"
#   namespace  = var.dependencies_namespace

#   set {
#     name  = "provider.name"
#     value = "google"
#   }

#   set {
#     name  = "policy"
#     value = "sync"
#   }

#   set {
#     name  = "google.project"
#     value = var.gcp_project_id
#   }

#   set {
#     name  = "domainFilters[0]"
#     value = "${var.gcp_dns_zone}."
#   }

#   set {
#     name  = "txtOwnerId"
#     value = "${var.gcp_dns_zone}."
#   }

#   set {
#     name  = "serviceAccount.create"
#     value = false
#   }

#   set {
#     name  = "serviceAccount.name"
#     value = var.dns_workload_identity
#   }

#   set {
#     name = "sources"
#     value = "{service}"
#   }

#   depends_on = [module.dns_workload_identity]
# }