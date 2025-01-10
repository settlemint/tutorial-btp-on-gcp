module "gcp_dns_zone" {
  source  = "terraform-google-modules/cloud-dns/google"
  version = "5.3.0"

  project_id = var.gcp_project_id
  type       = "public"
  name       = var.gcp_platform_name
  domain     = "${var.gcp_dns_zone}."
}
