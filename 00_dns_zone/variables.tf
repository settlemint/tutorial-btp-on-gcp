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
  default     = "europe-west1"
}

variable "gcp_dns_zone" {
  type        = string
  description = "Public DNS zone"
  nullable    = false
}
