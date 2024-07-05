resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.28.0"
  namespace        = var.dependencies_namespace
  create_namespace = true

  set {
    name  = "server.dataStorage.size"
    value = "1Gi"
  }

  depends_on = [module.gke]
}

resource "kubernetes_role" "vault_access" {
  metadata {
    name      = "vault-access"
    namespace = var.dependencies_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }
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

kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault operator init -key-shares=1 -key-threshold=1 > /mnt/vault-init.txt
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
  depends_on = [helm_release.vault]
}

data "kubernetes_config_map" "vault_init_output" {
  metadata {
    name      = "vault-init-output"
    namespace = var.dependencies_namespace
  }

  depends_on = [kubernetes_job.vault_init]
}

locals {
  unseal_key = regex("Unseal Key 1: (.+)", data.kubernetes_config_map.vault_init_output.data["vault-init.txt"])[0]
  root_token = regex("Initial Root Token: (.+)", data.kubernetes_config_map.vault_init_output.data["vault-init.txt"])[0]
}

resource "kubernetes_job" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = var.dependencies_namespace
  }
  spec {
    template {
      metadata {
        name = "vault-unseal"
      }
      spec {
        container {
          name  = "vault-unseal"
          image = "bitnami/kubectl:latest"
          command = [
            "sh", "-c",
            "kubectl exec vault-0 -n ${var.dependencies_namespace} -- vault operator unseal ${local.unseal_key}"
          ]
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 0
  }
  depends_on = [kubernetes_job.vault_init]
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
  depends_on = [kubernetes_job.vault_unseal]
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
