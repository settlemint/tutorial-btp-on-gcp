output "name_servers" {
  description = "The DNS zone name servers."

  value = module.gcp_dns_zone.name_servers
}