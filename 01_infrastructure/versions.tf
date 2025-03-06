terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "2.1.3"
    }
  }
  required_version = "1.11.1"
}
