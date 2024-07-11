data "google_client_config" "default" {}

resource "random_id" "platform_suffix" {
  byte_length = 4
}

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google"
  version = "~> 31.0"

  project_id        = var.gcp_project_id
  name              = var.gcp_platform_name
  regional          = true
  region            = var.gcp_region
  network           = "default"
  subnetwork        = "default"
  ip_range_pods     = null
  ip_range_services = null

  release_channel = "STABLE"

  node_pools = [
    {
      name         = "default-node-pool"
      machine_type = "e2-standard-4"
      min_count    = 1
      max_count    = 50
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      image_type   = "COS_CONTAINERD"
      auto_repair  = true
      auto_upgrade = true
    }
  ]

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/trace.append"
    ]
  }

  enable_cost_allocation      = false // Not specified in gcloud command
  enable_binary_authorization = false // Disabled in gcloud command
  gcs_fuse_csi_driver         = false // Not specified in gcloud command
  deletion_protection         = false
  enable_shielded_nodes       = true

  // Additional settings
  remove_default_node_pool   = true
  initial_node_count         = 1
  default_max_pods_per_node  = 110
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  network_policy             = false

  // Addons
  dns_cache         = false
  gce_pd_csi_driver = true
}


resource "kubernetes_namespace" "cluster_dependencies_namespace" {
  depends_on = [module.gke]
  metadata {
    annotations = {
      name = var.dependencies_namespace
    }

    name = var.dependencies_namespace
  }
}

resource "kubernetes_namespace" "deployment_namespace" {
  depends_on = [module.gke]
  metadata {
    annotations = {
      name = var.deployment_namespace
    }

    name = var.deployment_namespace
  }
}

resource "kubernetes_namespace" "settlemint" {
  depends_on = [module.gke]
  metadata {
    annotations = {
      name = "settlemint"
    }

    name = "settlemint"
  }
}

module "cert_manager_workload_identity" {
  source                          = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  use_existing_k8s_sa             = false
  cluster_name                    = "${var.gcp_platform_name}-${random_id.platform_suffix.hex}"
  location                        = var.gcp_region
  name                            = "${var.cert_manager_workload_identity}-${random_id.platform_suffix.hex}"
  roles                           = ["roles/dns.admin"]
  namespace                       = var.dependencies_namespace
  project_id                      = var.gcp_project_id
  automount_service_account_token = true
  depends_on                      = [kubernetes_namespace.cluster_dependencies_namespace]
}

module "external_dns_workload_identity" {
  source                          = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  use_existing_k8s_sa             = false
  cluster_name                    = "${var.gcp_platform_name}-${random_id.platform_suffix.hex}"
  location                        = var.gcp_region
  name                            = "${var.external_dns_workload_identity}-${random_id.platform_suffix.hex}"
  roles                           = ["roles/dns.admin"]
  namespace                       = "settlemint"
  project_id                      = var.gcp_project_id
  automount_service_account_token = true
  depends_on                      = [kubernetes_namespace.settlemint]
}

# Create the KMS Key Ring
resource "google_kms_key_ring" "vault_key_ring" {
  name     = "${var.gcp_key_ring_name}-${random_id.platform_suffix.hex}"
  project  = var.gcp_project_id
  location = var.gcp_region
}

# Create the KMS Crypto Key
resource "google_kms_crypto_key" "vault_crypto_key" {
  name     = var.gcp_crypto_key_name
  key_ring = google_kms_key_ring.vault_key_ring.id
}
