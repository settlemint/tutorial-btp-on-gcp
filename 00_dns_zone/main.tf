# ============================================================================
# DNS ZONE INFRASTRUCTURE MODULE
# ============================================================================
# 
# This module provisions the foundational DNS infrastructure for SettleMint's
# Blockchain Transformation Platform (BTP) deployment on Google Cloud Platform.
# 
# OVERVIEW:
# This module creates a public DNS managed zone that serves as the DNS authority
# for the BTP platform domain. This DNS zone is critical for:
# - SSL certificate provisioning via Let's Encrypt ACME challenges
# - Service discovery and routing for BTP applications
# - Load balancer endpoint resolution
# - Subdomain management for multi-tenant blockchain environments
# 
# ARCHITECTURE ROLE:
# In the overall BTP deployment architecture, this DNS zone acts as the 
# foundational layer that enables:
# 1. Secure HTTPS communication through automated certificate management
# 2. Dynamic service routing via ingress controllers
# 3. Multi-environment support (dev, staging, prod) through subdomains
# 4. External access to blockchain nodes and BTP services
# 
# DEPLOYMENT SEQUENCE:
# This module MUST be deployed first in the BTP infrastructure pipeline:
# 1. DNS Zone (this module) - Establishes domain authority
# 2. Infrastructure module - Creates GKE cluster and supporting services
# 3. Application deployment - Deploys BTP platform components
# 
# DEPENDENCIES:
# - Google Cloud DNS API must be enabled in the target project
# - Terraform service account requires dns.admin role
# - Domain must be registered and nameservers configured (post-deployment)
# 
# CONFIGURATION REQUIREMENTS:
# Enterprise architects and DevOps teams must configure:
# - var.gcp_project_id: Target GCP project for DNS zone
# - var.gcp_platform_name: Unique identifier for the BTP instance
# - var.gcp_dns_zone: Fully qualified domain name for the platform
# 
# SECURITY CONSIDERATIONS:
# - DNS zone is public by design to support Let's Encrypt validation
# - Access control managed via GCP IAM roles
# - DNS records are automatically managed by cert-manager and external-dns
# 
# COST IMPLICATIONS:
# - Google Cloud DNS charges per managed zone ($0.20/month)
# - Additional charges apply per million queries ($0.40/million)
# - Consider DNS query patterns when estimating operational costs
# 
# ============================================================================

# Google Cloud DNS Managed Zone
# Creates a public DNS zone that will serve as the authoritative DNS server
# for the BTP platform domain. This zone enables automatic DNS record
# management by Kubernetes controllers (cert-manager, external-dns).
module "gcp_dns_zone" {
  # Use the official Google Cloud DNS Terraform module
  # This module provides best practices for DNS zone configuration
  # and integrates seamlessly with other Google Cloud services
  source  = "terraform-google-modules/cloud-dns/google"
  version = "7.1.0"

  # Target GCP project where the DNS zone will be created
  # Must have Cloud DNS API enabled and appropriate IAM permissions
  project_id = var.gcp_project_id
  
  # DNS zone type - 'public' makes this zone resolvable from the internet
  # This is required for Let's Encrypt certificate validation and external access
  type       = "public"
  
  # DNS zone name - used as the resource identifier in GCP
  # Typically matches the platform name for consistency
  name       = var.gcp_platform_name
  
  # Domain name for the DNS zone - MUST end with a dot (.)
  # This is the FQDN that will be managed by this DNS zone
  # All BTP services will be accessible under this domain
  domain     = "${var.gcp_dns_zone}."
}
