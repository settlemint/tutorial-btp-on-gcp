resource "random_password" "minio_root_password" {
  length  = 16
  special = false
}

resource "random_password" "minio_provisioning_password" {
  length  = 16
  special = false
}

resource "random_password" "minio_svcacct_access_key" {
  length  = 16
  special = false
}

resource "random_password" "minio_svcacct_secret_key" {
  length  = 16
  special = false
}

resource "helm_release" "minio" {
  name       = "minio"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "minio"
  version    = "16.0.0"
  namespace  = var.dependencies_namespace

  create_namespace = true

  set {
    name  = "defaultBuckets"
    value = var.gcp_platform_name
  }

  set {
    name  = "disableWebUI"
    value = "false"
  }

  set {
    name  = "auth.rootUser"
    value = var.gcp_platform_name
  }

  set {
    name  = "auth.rootPassword"
    value = random_password.minio_root_password.result
  }

  set {
    name  = "statefulset.replicaCount"
    value = "1"
  }

  set {
    name  = "provisioning.enabled"
    value = "true"
  }

  set {
    name  = "provisioning.config[0].name"
    value = "region"
  }

  set {
    name  = "provisioning.config[0].options.name"
    value = var.gcp_region
  }

  set {
    name  = "provisioning.users[0].username"
    value = "pulumi"
  }

  set {
    name  = "provisioning.users[0].password"
    value = random_password.minio_provisioning_password.result
  }

  set {
    name  = "provisioning.users[0].disabled"
    value = "false"
  }

  set {
    name  = "provisioning.users[0].policies[0]"
    value = "readwrite"
  }

  set {
    name  = "provisioning.users[0].setPolicies"
    value = "true"
  }

  set_sensitive {
    name  = "provisioning.extraCommands"
    value = "if [[ ! $(mc admin user svcacct ls provisioning ${var.gcp_platform_name} | grep ${random_password.minio_svcacct_access_key.result}) ]]; then mc admin user svcacct add --access-key \"${random_password.minio_svcacct_access_key.result}\" --secret-key \"${random_password.minio_svcacct_secret_key.result}\" provisioning ${var.gcp_platform_name}; fi"
  }

  depends_on = [module.gke, kubernetes_namespace.cluster_dependencies_namespace]
}