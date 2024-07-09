variable "oci_registry_username" {
  type        = string
  description = "The username for the SettleMint OCI registry"
  nullable    = false
}

variable "oci_registry_password" {
  type        = string
  description = "The password for the SettleMint OCI registry"
  nullable    = false
  sensitive   = true
}

variable "btp_version" {
  type        = string
  default     = "v7.6.19"
  description = "The version of the SettleMint Blockchain Transformation Platform to install"
  nullable    = false
}

variable "gcp_project_id" {
  type        = string
  description = "The Google Cloud Platform project ID"
  nullable    = false
}

variable "gcp_platform_name" {
  type        = string
  description = "The name of the Kubernetes cluster, dns zone, etc"
  default     = "btp"
}

variable "gcp_region" {
  type        = string
  description = "The region to create the resources in"
  nullable    = false
}

variable "gcp_dns_zone" {
  type        = string
  description = "Public DNS zone"
  nullable    = false
}

variable "dependencies_namespace" {
  type        = string
  description = "Namespace where cluster dependencies will install in"
  default     = "cluster-dependencies"
}

variable "deployment_namespace" {
  type        = string
  description = "Namespace where btp services deploy"
  default     = "deployments"
}

variable "cert_manager_workload_identity" {
  type        = string
  description = "Name of the cert-manager workload identity GCP service account"
  default     = "cert-manager"
}

variable "external_dns_workload_identity" {
  type        = string
  description = "Name of the external-dns workload identity GCP service account"
  default     = "external-dns"
}

variable "vault_unseal_workload_identity" {
  type        = string
  description = "Name of the vault unseal workload identity GCP service account"
  default     = "vault-unseal"
}

variable "gcp_client_id" {
  type        = string
  description = "OAuth gcp client id"
  nullable    = false
}

variable "gcp_client_secret" {
  type        = string
  description = "OAuth gcp client secret"
  nullable    = false
}

variable "gcp_key_ring_name" {
  description = "The name of the KMS key ring"
  type        = string
  default     = "vault-key-ring"
}

variable "gcp_crypto_key_name" {
  description = "The name of the KMS crypto key"
  type        = string
  default     = "vault-key"
}

variable "vault_gcp_sa" {
  description = "The name of the vault configmap with GCP service account key"
  type        = string
  default     = "vault-gcp-sa"
}