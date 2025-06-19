resource "helm_release" "cert_manager" {
  name = "cert-manager"

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.18.1"
  namespace  = var.dependencies_namespace

  set {
    name  = "serviceAccount.create"
    value = false
  }

  set {
    name  = "serviceAccount.name"
    value = "${var.cert_manager_workload_identity}-${random_id.platform_suffix.hex}"
  }

  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [module.cert_manager_workload_identity, kubernetes_namespace.cluster_dependencies_namespace]
}


resource "kubectl_manifest" "cluster_issuer" {

  validate_schema = false
  yaml_body       = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
  namespace: ${var.dependencies_namespace}
spec:
  acme:
    email: trial-demo@settlemint.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource that will be used to store the account's private key.
      name: example-issuer-account-key
    solvers:
    - dns01:
        cloudDNS:
          project: ${var.gcp_project_id}
YAML

  depends_on = [helm_release.cert_manager]
}


resource "kubectl_manifest" "certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${var.gcp_platform_name}
  namespace: ${var.dependencies_namespace}
spec:
  secretName: nginx-tls-secret
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - ${var.gcp_dns_zone}
  - "*.${var.gcp_dns_zone}"
YAML

  depends_on = [kubectl_manifest.cluster_issuer]
}