module "service_accounts" {
  source        = "terraform-google-modules/service-accounts/google"
  version       = "4.5.4"
  project_id    = var.gcp_project_id
  prefix        = "vault-${random_id.platform_suffix.hex}"
  names         = ["unseal-sa"]
  project_roles = [
    "${var.gcp_project_id}=>roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "${var.gcp_project_id}=>roles/cloudkms.viewer",
  ]
  generate_keys = true
}

resource "kubernetes_config_map" "vault_gcp_sa" {
  metadata {
    name      = var.vault_gcp_sa
    namespace = var.dependencies_namespace
  }

  data = {
    "credentials.json" = module.service_accounts.keys["unseal-sa"]
  }
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.30.0"
  namespace        = var.dependencies_namespace
  create_namespace = true

  set {
    name  = "server.dataStorage.size"
    value = "1Gi"
  }

  set {
    name  = "server.extraEnvironmentVars.GOOGLE_REGION"
    value = var.gcp_region
  }

  set {
    name  = "server.extraEnvironmentVars.GOOGLE_PROJECT"
    value = var.gcp_project_id
  }

  set {
    name  = "server.extraEnvironmentVars.GOOGLE_APPLICATION_CREDENTIALS"
    value = "/vault/userconfig/vault-gcp-sa/credentials.json"
  }

  set {
    name  = "server.volumes[0].name"
    value = var.vault_gcp_sa
  }

  set {
    name  = "server.volumes[0].configMap.name"
    value = kubernetes_config_map.vault_gcp_sa.metadata[0].name
  }

  set {
    name  = "server.volumeMounts[0].name"
    value = var.vault_gcp_sa
  }

  set {
    name  = "server.volumeMounts[0].mountPath"
    value = "/vault/userconfig/${var.vault_gcp_sa}"
  }

  set {
    name  = "server.standalone.config"
    value = <<-EOT
      ui = true

      listener "tcp" {
        tls_disable = 1
        address = "[::]:8200"
        cluster_address = "[::]:8201"
        # Enable unauthenticated metrics access (necessary for Prometheus Operator)
        #telemetry {
        #  unauthenticated_metrics_access = "true"
        #}
      }
      storage "file" {
        path = "/vault/data"
      }

      seal "gcpckms" {
        project     = "${var.gcp_project_id}"
        region      = "${var.gcp_region}"
        key_ring    = "${var.gcp_key_ring_name}-${random_id.platform_suffix.hex}"
        crypto_key  = "${var.gcp_crypto_key_name}"
      }
    EOT
  }

  depends_on = [module.gke, google_kms_crypto_key.vault_crypto_key, kubernetes_namespace.cluster_dependencies_namespace, google_kms_key_ring.vault_key_ring]
}

resource "kubernetes_role" "vault_access" {
  metadata {
    name      = "vault-access"
    namespace = var.dependencies_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec", "pods/log", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  depends_on = [ helm_release.vault ]
}

resource "kubernetes_role_binding" "vault_access_binding" {
  metadata {
    name      = "vault-access-binding"
    namespace = var.dependencies_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vault_access.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = var.dependencies_namespace
  }
  depends_on = [ helm_release.vault ]
}

resource "kubernetes_job" "vault_init" {
  metadata {
    name      = "vault-init"
    namespace = var.dependencies_namespace
  }
  spec {
    template {
      metadata {
        name = "vault-init"
      }
      spec {
        service_account_name = "default"
        container {
          name  = "vault-init"
          image = "bitnami/kubectl:latest"
          command = [
            "sh", "-c",
            <<EOF
while [ "$(kubectl get pod vault-0 -n ${var.dependencies_namespace} -o jsonpath='{.status.phase}')" != "Running" ]; do
  echo "Waiting for vault-0 pod to be in Running state..."
  sleep 2
done


if kubectl get configmap vault-init-output -n ${var.dependencies_namespace}; then
  kubectl delete configmap vault-init-output -n ${var.dependencies_namespace}
fi

kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault operator init > /mnt/vault-init.txt
cat /mnt/vault-init.txt
kubectl create configmap vault-init-output -n ${var.dependencies_namespace} --from-file=/mnt/vault-init.txt
EOF
          ]
          volume_mount {
            name       = "vault-init"
            mount_path = "/mnt"
          }
        }
        volume {
          name = "vault-init"
          empty_dir {}
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 0
  }
  depends_on = [helm_release.vault, google_kms_crypto_key.vault_crypto_key]
}

data "kubernetes_config_map" "vault_init_output" {
  metadata {
    name      = "vault-init-output"
    namespace = var.dependencies_namespace
  }

  depends_on = [kubernetes_job.vault_init]
}

locals {
  root_token = regex("Initial Root Token: (.+)", data.kubernetes_config_map.vault_init_output.data["vault-init.txt"])[0]
}

resource "kubernetes_job" "vault_configure" {
  metadata {
    name      = "vault-configure"
    namespace = var.dependencies_namespace
  }
  spec {
    template {
      metadata {
        name = "vault-configure"
      }
      spec {
        container {
          name  = "vault-configure"
          image = "bitnami/kubectl:latest"
          env {
            name  = "VAULT_TOKEN"
            value = local.root_token
          }
          command = [
            "sh", "-c",
            <<EOF
echo 'kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault login ${local.root_token}
if ! kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault secrets list | grep -q "ethereum/"; then
  kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault secrets enable -path=ethereum kv-v2
fi
if ! kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault secrets list | grep -q "ipfs/"; then
  kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault secrets enable -path=ipfs kv-v2
fi
if ! kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault secrets list | grep -q "fabric/"; then
  kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault secrets enable -path=fabric kv-v2
fi
if ! kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault auth list | grep -q "approle/"; then
  kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault auth enable approle
fi
echo "path \\"ethereum/*\\" {
  capabilities = [\\"create\\", \\"read\\", \\"update\\", \\"delete\\", \\"list\\"]
}" > /tmp/ethereum-policy.hcl
kubectl cp /tmp/ethereum-policy.hcl ${var.dependencies_namespace}/vault-0:/tmp/ethereum-policy.hcl
kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault policy write ethereum /tmp/ethereum-policy.hcl
echo "path \\"ipfs/*\\" {
  capabilities = [\\"create\\", \\"read\\", \\"update\\", \\"delete\\", \\"list\\"]
}" > /tmp/ipfs-policy.hcl
kubectl cp /tmp/ipfs-policy.hcl ${var.dependencies_namespace}/vault-0:/tmp/ipfs-policy.hcl
kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault policy write ipfs /tmp/ipfs-policy.hcl
echo "path \\"fabric/*\\" {
  capabilities = [\\"create\\", \\"read\\", \\"update\\", \\"delete\\", \\"list\\"]
}" > /tmp/fabric-policy.hcl
kubectl cp /tmp/fabric-policy.hcl ${var.dependencies_namespace}/vault-0:/tmp/fabric-policy.hcl
kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault policy write fabric /tmp/fabric-policy.hcl
kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault write auth/approle/role/platform-role token_ttl=1h token_max_ttl=4h secret_id_ttl=0 policies="ethereum,ipfs,fabric"' > /tmp/vault-configure.sh
sh /tmp/vault-configure.sh
EOF
          ]
          volume_mount {
            name       = "vault-configure"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "vault-configure"
          empty_dir {}
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 0
  }
  depends_on = [kubernetes_job.vault_init]
}

resource "kubernetes_job" "vault_get_approle_ids" {
  metadata {
    name      = "vault-get-approle-ids"
    namespace = var.dependencies_namespace
  }
  spec {
    template {
      metadata {
        name = "vault-get-approle-ids"
      }
      spec {
        service_account_name = "default"
        container {
          name  = "vault-get-approle-ids"
          image = "bitnami/kubectl:latest"
          command = [
            "sh", "-c",
            <<EOF
role_id=`kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault read -field=role_id auth/approle/role/platform-role/role-id`
secret_id=`kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault write -force -field=secret_id auth/approle/role/platform-role/secret-id`

echo "role_id=$${role_id}" > /mnt/vault-approle-ids.txt
echo "secret_id=$${secret_id}" >> /mnt/vault-approle-ids.txt

if kubectl get configmap vault-approle-ids -n ${var.dependencies_namespace}; then
  kubectl delete configmap vault-approle-ids -n ${var.dependencies_namespace}
fi

kubectl create configmap vault-approle-ids -n ${var.dependencies_namespace} --from-file=/mnt/vault-approle-ids.txt
EOF
          ]
          volume_mount {
            name       = "vault-get-approle-ids"
            mount_path = "/mnt"
          }
        }
        volume {
          name = "vault-get-approle-ids"
          empty_dir {}
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 0
  }
  depends_on = [kubernetes_job.vault_configure]
}

data "kubernetes_config_map" "vault_approle_ids" {
  metadata {
    name      = "vault-approle-ids"
    namespace = var.dependencies_namespace
  }

  depends_on = [kubernetes_job.vault_get_approle_ids]
}

locals {
  role_id   = regex("role_id=(.+)", data.kubernetes_config_map.vault_approle_ids.data["vault-approle-ids.txt"])[0]
  secret_id = regex("secret_id=(.+)", data.kubernetes_config_map.vault_approle_ids.data["vault-approle-ids.txt"])[0]
}
