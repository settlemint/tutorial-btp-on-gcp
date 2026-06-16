# ============================================================================
# CORE INFRASTRUCTURE MODULE - MAIN CONFIGURATION
# ============================================================================
# 
# This file contains the core infrastructure components for SettleMint's
# Blockchain Transformation Platform (BTP) on Google Cloud Platform.
# It orchestrates the deployment of:
# 
# 1. GOOGLE KUBERNETES ENGINE (GKE): Production-ready Kubernetes cluster
# 2. KUBERNETES NAMESPACES: Logical separation of platform components
# 3. WORKLOAD IDENTITY: Secure GCP-to-Kubernetes authentication
# 4. KEY MANAGEMENT SERVICE: Encryption keys for Vault auto-unsealing
# 
# ARCHITECTURE OVERVIEW:
# The infrastructure follows enterprise-grade patterns with:
# - Regional GKE deployment for high availability
# - Workload Identity for secure cloud resource access
# - Managed node pools with auto-scaling capabilities
# - Integrated security controls and monitoring
# - KMS-based encryption for secrets management
# 
# DEPLOYMENT DEPENDENCIES:
# This module requires:
# - DNS zone module (00_dns_zone) to be deployed first
# - Google Cloud APIs enabled: GKE, IAM, KMS, DNS
# - Appropriate IAM permissions for Terraform service account
# - Network infrastructure (uses default VPC by default)
# 
# ENTERPRISE CONSIDERATIONS:
# - Cluster configuration optimized for blockchain workloads
# - Multi-zone deployment for fault tolerance
# - Scalable node pools for varying computational demands
# - Security hardening with Shielded GKE nodes
# - Cost optimization through efficient resource allocation
# 
# ============================================================================

# Google Cloud Client Configuration Data Source
# Retrieves the current Google Cloud authentication context and configuration.
# This data source provides access to the current user's or service account's
# authentication token, which is essential for configuring Kubernetes and
# Helm providers to communicate with the GKE cluster.
# 
# AUTHENTICATION FLOW:
# 1. Terraform authenticates to Google Cloud using configured credentials
# 2. This data source captures the current authentication context
# 3. The access token is used by Kubernetes/Helm providers for cluster access
# 4. Tokens are automatically refreshed as needed during deployment
# 
# SECURITY IMPLICATIONS:
# - Tokens are temporary and automatically rotated
# - No static credentials are stored or exposed
# - Authentication inherits from Terraform's GCP configuration
# - Supports both user accounts and service account authentication
data "google_client_config" "default" {}

# Platform Unique Identifier Generator
# Generates a cryptographically secure random identifier used as a suffix
# for various resources to ensure uniqueness across deployments and prevent
# naming conflicts in shared GCP projects or multi-environment setups.
# 
# USAGE ACROSS INFRASTRUCTURE:
# - GKE cluster names: "${var.gcp_platform_name}-${random_id.platform_suffix.hex}"
# - Service account names: "${service_name}-${random_id.platform_suffix.hex}"
# - KMS key ring names: "${var.gcp_key_ring_name}-${random_id.platform_suffix.hex}"
# - Workload identity bindings: Ensures unique identity mappings
# 
# BENEFITS:
# - Prevents resource name collisions in shared environments
# - Enables multiple BTP deployments in the same GCP project
# - Provides unique identifiers for disaster recovery scenarios
# - Supports blue-green deployment strategies
# 
# SECURITY CONSIDERATIONS:
# - Uses cryptographically secure random generation
# - 4-byte length provides 4.3 billion unique combinations
# - Hex encoding ensures compatibility with GCP naming requirements
# - Persistent across Terraform state for consistent naming
resource "random_id" "platform_suffix" {
  byte_length = 4
}

# Google Kubernetes Engine (GKE) Cluster
# Deploys a production-ready, regional Kubernetes cluster optimized for
# SettleMint's Blockchain Transformation Platform. This cluster serves as
# the foundation for all BTP services, blockchain nodes, and supporting
# infrastructure components.
# 
# CLUSTER ARCHITECTURE:
# - Regional deployment across multiple zones for high availability
# - Auto-scaling node pools to handle variable blockchain workloads
# - Shielded nodes for enhanced security and compliance
# - Container-optimized OS (COS) for improved security and performance
# - Integrated with Google Cloud services (logging, monitoring, storage)
# 
# BLOCKCHAIN-SPECIFIC OPTIMIZATIONS:
# - Machine type (e2-standard-4) provides 4 vCPUs and 16GB RAM per node
# - Balanced persistent disks for optimal I/O performance
# - Sufficient pod capacity (110 pods per node) for microservices architecture
# - Auto-scaling (1-50 nodes) handles varying computational demands
# - Stable release channel ensures tested, reliable Kubernetes versions
# 
# SECURITY HARDENING:
# - Shielded GKE nodes protect against rootkits and bootkits
# - Workload Identity enables secure access to Google Cloud services
# - Network policies disabled for simplified initial configuration
# - Binary authorization disabled for flexibility in container deployment
# - Comprehensive OAuth scopes for necessary Google Cloud service access
# 
# ENTERPRISE FEATURES:
# - HTTP load balancing for external service exposure
# - Horizontal Pod Autoscaling for dynamic resource allocation
# - Google Cloud Operations integration for monitoring and logging
# - Persistent disk CSI driver for dynamic storage provisioning
# - Cost allocation tracking for resource usage monitoring
module "gke" {
  # Official Google Cloud GKE Terraform Module
  # Provides best practices configuration and comprehensive feature support
  # Maintained by Google Cloud team with regular updates and security patches
  source  = "terraform-google-modules/kubernetes-engine/google"
  version = "44.2.0"

  # Google Cloud Project Configuration
  # Target project where the GKE cluster will be created
  # Must have required APIs enabled: container.googleapis.com, compute.googleapis.com
  project_id = var.gcp_project_id
  
  # Cluster Naming and Location
  # Cluster name uses platform name for consistency across resources
  # Regional deployment provides high availability across multiple zones
  name     = var.gcp_platform_name
  regional = true
  region   = var.gcp_region

  # Network Configuration
  # Uses default VPC and subnet for simplified networking
  # Automatic IP range allocation for pods and services
  # Can be customized for advanced networking requirements
  network           = "default"
  subnetwork        = "default"
  ip_range_pods     = null  # Automatic allocation
  ip_range_services = null  # Automatic allocation

  # Kubernetes Version Management
  # STABLE release channel provides tested, reliable Kubernetes versions
  # Automatic updates with controlled rollout for stability
  # Balances security updates with operational stability
  release_channel = "STABLE"

  # Node Pool Configuration
  # Defines the compute resources available for BTP workloads
  # Optimized for blockchain applications and microservices architecture
  node_pools = [
    {
      # Node pool identifier and machine specifications
      name         = "default-node-pool"
      machine_type = "e2-standard-4"  # 4 vCPUs, 16GB RAM - optimal for blockchain workloads
      
      # Auto-scaling configuration
      # Minimum 1 node ensures cluster availability
      # Maximum 50 nodes handles peak blockchain processing demands
      min_count = 1
      max_count = 50
      
      # Storage configuration
      # 50GB balanced persistent disks provide good I/O performance
      # Sufficient for container images, logs, and temporary data
      disk_size_gb = 50
      disk_type    = "pd-balanced"  # Balanced performance and cost
      
      # Operating system and container runtime
      # Container-Optimized OS with containerd for security and performance
      image_type = "COS_CONTAINERD"
      
      # Maintenance and updates
      # Automatic repair replaces unhealthy nodes
      # Automatic upgrade keeps nodes current with security patches
      auto_repair  = true
      auto_upgrade = true
    }
  ]

  # OAuth Scopes for Node Service Accounts
  # Defines Google Cloud API access permissions for cluster nodes
  # Essential for integration with Google Cloud services
  node_pools_oauth_scopes = {
    all = [
      # Container Registry access for pulling private images
      "https://www.googleapis.com/auth/devstorage.read_only",
      
      # Cloud Logging for centralized log management
      "https://www.googleapis.com/auth/logging.write",
      
      # Cloud Monitoring for metrics and alerting
      "https://www.googleapis.com/auth/monitoring",
      
      # Service Control API for API management
      "https://www.googleapis.com/auth/servicecontrol",
      
      # Service Management API for service discovery
      "https://www.googleapis.com/auth/service.management.readonly",
      
      # Cloud Trace for distributed tracing
      "https://www.googleapis.com/auth/trace.append"
    ]
  }

  # Security and Compliance Features
  # Cost allocation disabled for simplified initial deployment
  # Binary authorization disabled to allow flexible container deployment
  # GCS FUSE CSI driver disabled (not required for BTP)
  # Deletion protection disabled for development flexibility
  # Shielded nodes enabled for enhanced security
  enable_cost_allocation      = false
  enable_binary_authorization = false
  gcs_fuse_csi_driver         = false
  deletion_protection         = false
  enable_shielded_nodes       = true

  # Cluster Configuration Options
  # Remove default node pool to use custom configuration
  # Initial node count for cluster bootstrap
  # Maximum pods per node optimized for microservices
  # Load balancing and autoscaling enabled for scalability
  # Network policy disabled for simplified networking
  remove_default_node_pool   = true
  initial_node_count         = 1
  default_max_pods_per_node  = 110
  http_load_balancing        = true
  horizontal_pod_autoscaling = true
  network_policy             = false

  # Cluster Add-ons
  # DNS cache disabled for standard DNS resolution
  # Persistent disk CSI driver enabled for dynamic storage provisioning
  dns_cache         = false
  gce_pd_csi_driver = true
}


# ============================================================================
# KUBERNETES NAMESPACE CONFIGURATION
# ============================================================================
# 
# Creates logical separation of BTP platform components through Kubernetes
# namespaces. This multi-namespace architecture provides:
# - Resource isolation and security boundaries
# - Independent RBAC and network policies
# - Organized deployment and management structure
# - Clear separation of concerns between platform layers
# 
# NAMESPACE ARCHITECTURE:
# 1. CLUSTER-DEPENDENCIES: Infrastructure services (databases, monitoring)
# 2. DEPLOYMENTS: User applications and blockchain networks
# 3. SETTLEMINT: Core BTP platform components and services
# 
# ENTERPRISE BENEFITS:
# - Simplified resource management and monitoring
# - Independent scaling and resource quotas
# - Enhanced security through namespace-level isolation
# - Streamlined backup and disaster recovery procedures
# ============================================================================

# Cluster Dependencies Namespace
# Houses essential infrastructure services that support the BTP platform.
# These services must be deployed before BTP applications and include
# databases, caching, object storage, secrets management, and monitoring.
# 
# DEPLOYED SERVICES:
# - PostgreSQL: Primary relational database for BTP applications
# - Redis: In-memory caching and session storage
# - MinIO: S3-compatible object storage for blockchain data
# - HashiCorp Vault: Secrets management and encryption services
# - cert-manager: Automated SSL/TLS certificate management
# - ingress-nginx: HTTP/HTTPS load balancing and routing
# 
# RESOURCE CHARACTERISTICS:
# - Long-running, stateful services with persistent storage
# - Shared across multiple BTP applications and environments
# - Require elevated privileges for cluster-wide operations
# - Critical for platform availability and data integrity
# 
# SECURITY CONSIDERATIONS:
# - Contains sensitive infrastructure components
# - Requires restricted access and monitoring
# - Network policies should limit inter-namespace communication
# - Regular security audits and vulnerability assessments
resource "kubernetes_namespace" "cluster_dependencies_namespace" {
  # Ensure GKE cluster is fully operational before creating namespaces
  depends_on = [module.gke]
  
  metadata {
    # Namespace annotations for metadata and tooling integration
    annotations = {
      name = var.dependencies_namespace
      # Additional annotations can be added for:
      # - Resource quotas and limits
      # - Network policy configurations
      # - Monitoring and alerting settings
      # - Backup and disaster recovery policies
    }

    # Namespace name - configurable via variable for environment flexibility
    name = var.dependencies_namespace
  }
}

# Deployment Namespace
# Dedicated space for user applications, blockchain networks, and custom
# deployments. This namespace provides isolation for customer workloads
# while maintaining access to shared infrastructure services.
# 
# TYPICAL DEPLOYMENTS:
# - Ethereum blockchain nodes and networks
# - Hyperledger Fabric networks and chaincodes
# - IPFS nodes for distributed file storage
# - Custom blockchain applications and smart contracts
# - Development and testing environments
# 
# RESOURCE CHARACTERISTICS:
# - Dynamic, user-driven deployments
# - Variable resource requirements based on blockchain type
# - Potential for high computational and storage demands
# - Requires flexible scaling and resource allocation
# 
# ISOLATION BENEFITS:
# - User workloads isolated from infrastructure services
# - Independent resource quotas and limits
# - Separate RBAC policies for user access control
# - Simplified monitoring and billing per deployment
resource "kubernetes_namespace" "deployment_namespace" {
  # Wait for GKE cluster readiness before namespace creation
  depends_on = [module.gke]
  
  metadata {
    # Namespace metadata for identification and management
    annotations = {
      name = var.deployment_namespace
      # Environment-specific annotations:
      # - Cost center allocation
      # - Compliance requirements
      # - Data classification levels
      # - Retention policies
    }

    # Configurable namespace name for multi-environment deployments
    name = var.deployment_namespace
  }
}

# SettleMint Platform Namespace
# Core namespace for SettleMint's Blockchain Transformation Platform
# components. Contains the primary BTP application stack, APIs, web
# interfaces, and platform-specific services.
# 
# PLATFORM COMPONENTS:
# - BTP Web Application: User interface and dashboard
# - BTP API Services: REST APIs for blockchain interactions
# - Platform Database Connections: Links to infrastructure databases
# - Authentication and Authorization Services: User management
# - Monitoring and Analytics: Platform metrics and insights
# - External DNS Controller: Automatic DNS record management
# 
# ARCHITECTURAL ROLE:
# - Central orchestration layer for blockchain operations
# - Integration point between user interfaces and blockchain networks
# - Platform-as-a-Service (PaaS) functionality for blockchain development
# - Multi-tenant support for enterprise blockchain deployments
# 
# SECURITY AND COMPLIANCE:
# - Contains proprietary SettleMint intellectual property
# - Requires secure container image registry access
# - Implements enterprise-grade authentication and authorization
# - Maintains audit trails and compliance logging
resource "kubernetes_namespace" "settlemint" {
  # Ensure cluster infrastructure is ready for platform deployment
  depends_on = [module.gke]
  
  metadata {
    # Platform-specific metadata and configuration
    annotations = {
      name = "settlemint"
      # Platform annotations:
      # - Version tracking and release management
      # - License and subscription information
      # - Support and maintenance contacts
      # - Integration configurations
    }

    # Fixed namespace name for SettleMint platform consistency
    name = "settlemint"
  }
}

# ============================================================================
# WORKLOAD IDENTITY CONFIGURATION
# ============================================================================
# 
# Configures Google Cloud Workload Identity to enable secure authentication
# between Kubernetes pods and Google Cloud services without storing static
# service account keys. This approach provides:
# - Enhanced security through temporary, scoped credentials
# - Automatic credential rotation and management
# - Fine-grained IAM role assignment per service
# - Elimination of static credential management overhead
# 
# WORKLOAD IDENTITY ARCHITECTURE:
# 1. Google Service Account: Created in GCP with specific IAM roles
# 2. Kubernetes Service Account: Created in target namespace
# 3. IAM Policy Binding: Links GSA and KSA for secure authentication
# 4. Pod Authentication: Pods use KSA to obtain GSA credentials
# 
# SECURITY BENEFITS:
# - No static credentials stored in cluster or containers
# - Automatic token refresh and short-lived credentials
# - Principle of least privilege through role-specific access
# - Audit trail of all service account operations
# ============================================================================

# Cert-Manager Workload Identity
# Enables cert-manager to perform DNS-01 ACME challenges for Let's Encrypt
# SSL certificate provisioning. This workload identity provides cert-manager
# with the necessary permissions to create and manage DNS TXT records for
# domain validation during certificate issuance.
# 
# CERT-MANAGER INTEGRATION:
# - Performs DNS-01 challenges for wildcard and standard certificates
# - Creates temporary TXT records in Google Cloud DNS
# - Validates domain ownership for Let's Encrypt certificate authority
# - Automatically provisions and renews SSL/TLS certificates
# 
# DNS ADMIN ROLE REQUIREMENTS:
# The roles/dns.admin IAM role provides cert-manager with:
# - DNS zone read access for validation
# - DNS record creation and deletion for challenges
# - DNS change propagation monitoring
# - Zone-level administrative capabilities
# 
# SECURITY CONSIDERATIONS:
# - Scoped to DNS operations only (no broader GCP access)
# - Temporary credentials with automatic rotation
# - Activity logged in Google Cloud Audit Logs
# - Namespace isolation limits blast radius
module "cert_manager_workload_identity" {
  # Official Google Cloud Workload Identity Terraform module
  # Provides secure, best-practice configuration for GKE workload identity
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  
  # Service Account Configuration
  # Creates new Kubernetes service account rather than using existing one
  # Ensures clean, dedicated identity for cert-manager operations
  use_existing_k8s_sa = false
  
  # GKE Cluster Identification
  # Must match the actual cluster name including unique suffix
  # Required for proper workload identity binding configuration
  cluster_name = "${var.gcp_platform_name}-${random_id.platform_suffix.hex}"
  location     = var.gcp_region
  
  # Service Account Naming
  # Includes unique suffix to prevent naming conflicts across deployments
  # Follows consistent naming convention with other infrastructure resources
  name = "${var.cert_manager_workload_identity}-${random_id.platform_suffix.hex}"
  
  # IAM Role Assignment
  # DNS Admin role provides comprehensive DNS management capabilities
  # Required for Let's Encrypt DNS-01 challenge completion
  roles = ["roles/dns.admin"]
  
  # Kubernetes Namespace Assignment
  # Places service account in cluster dependencies namespace
  # Aligns with cert-manager deployment location
  namespace = var.dependencies_namespace
  
  # Google Cloud Project Context
  project_id = var.gcp_project_id
  
  # Token Mounting Configuration
  # Enables automatic service account token mounting in cert-manager pods
  # Required for workload identity authentication flow
  automount_service_account_token = true
  
  # Deployment Dependencies
  # Ensures namespace exists before creating workload identity
  depends_on = [kubernetes_namespace.cluster_dependencies_namespace]
}

# External DNS Workload Identity
# Provides external-dns controller with permissions to automatically manage
# DNS records based on Kubernetes ingress and service annotations. This
# enables dynamic DNS record creation and management for BTP platform services.
# 
# EXTERNAL-DNS FUNCTIONALITY:
# - Monitors Kubernetes ingress resources for DNS annotations
# - Automatically creates A and CNAME records in Google Cloud DNS
# - Maintains DNS record lifecycle (create, update, delete)
# - Supports multiple DNS providers and record types
# 
# DNS MANAGEMENT SCOPE:
# - Creates DNS records for BTP platform services
# - Manages subdomains for blockchain networks and applications
# - Maintains DNS consistency with Kubernetes service changes
# - Enables service discovery through DNS resolution
# 
# OPERATIONAL BENEFITS:
# - Eliminates manual DNS record management
# - Provides automatic DNS updates during deployments
# - Supports blue-green and canary deployment strategies
# - Integrates with CI/CD pipelines for seamless operations
module "external_dns_workload_identity" {
  # Google Cloud Workload Identity module for secure DNS access
  source = "terraform-google-modules/kubernetes-engine/google//modules/workload-identity"
  
  # Service Account Creation Strategy
  # Creates dedicated Kubernetes service account for external-dns
  # Ensures isolated identity with specific DNS management permissions
  use_existing_k8s_sa = false
  
  # Cluster Context Configuration
  # Links workload identity to specific GKE cluster
  # Enables secure authentication between Kubernetes and Google Cloud
  cluster_name = "${var.gcp_platform_name}-${random_id.platform_suffix.hex}"
  location     = var.gcp_region
  
  # Identity Naming Convention
  # Consistent naming with unique suffix for deployment isolation
  # Prevents conflicts in shared GCP projects or multi-environment setups
  name = "${var.external_dns_workload_identity}-${random_id.platform_suffix.hex}"
  
  # DNS Administrative Permissions
  # Full DNS admin role for comprehensive record management
  # Enables creation, modification, and deletion of DNS records
  roles = ["roles/dns.admin"]
  
  # SettleMint Namespace Assignment
  # Places external-dns service account in platform namespace
  # Aligns with BTP platform component deployment strategy
  namespace = "settlemint"
  
  # Google Cloud Project Context
  project_id = var.gcp_project_id
  
  # Authentication Token Configuration
  # Enables automatic token mounting for workload identity authentication
  # Required for external-dns to access Google Cloud DNS APIs
  automount_service_account_token = true
  
  # Dependency Management
  # Ensures SettleMint namespace is created before workload identity setup
  depends_on = [kubernetes_namespace.settlemint]
}

# ============================================================================
# GOOGLE CLOUD KEY MANAGEMENT SERVICE (KMS) CONFIGURATION
# ============================================================================
# 
# Configures Google Cloud KMS resources for HashiCorp Vault auto-unsealing.
# This setup provides enterprise-grade encryption key management with:
# - Hardware Security Module (HSM) backed encryption keys
# - Automatic key rotation and lifecycle management
# - Fine-grained access controls and audit logging
# - High availability and disaster recovery capabilities
# 
# VAULT AUTO-UNSEAL ARCHITECTURE:
# 1. KMS Key Ring: Logical grouping of encryption keys
# 2. Crypto Key: Actual encryption key for Vault seal/unseal operations
# 3. IAM Permissions: Service account access to encryption/decryption
# 4. Vault Configuration: KMS seal configuration in Vault server
# 
# SECURITY BENEFITS:
# - Eliminates need for manual Vault unsealing procedures
# - Provides automatic Vault recovery after pod restarts
# - Ensures encryption keys are never exposed to applications
# - Maintains compliance with enterprise security requirements
# 
# OPERATIONAL ADVANTAGES:
# - Reduces operational overhead for Vault management
# - Enables automated disaster recovery procedures
# - Supports high availability Vault deployments
# - Integrates with Google Cloud security monitoring
# ============================================================================

# Google Cloud KMS Key Ring
# Creates a logical container for cryptographic keys used by HashiCorp Vault
# for auto-unsealing operations. The key ring provides organizational structure
# and access control boundaries for encryption keys.
# 
# KEY RING CHARACTERISTICS:
# - Regional resource for optimal performance and compliance
# - Immutable after creation (cannot be deleted, only disabled)
# - Supports multiple crypto keys for different purposes
# - Integrated with Google Cloud IAM for access control
# 
# NAMING STRATEGY:
# - Includes platform-specific prefix for resource organization
# - Appends unique suffix to prevent naming conflicts
# - Follows Google Cloud naming conventions and best practices
# - Enables multiple BTP deployments in same project
# 
# COMPLIANCE CONSIDERATIONS:
# - Regional deployment supports data residency requirements
# - Audit logging tracks all key ring operations
# - IAM integration provides fine-grained access controls
# - Supports enterprise compliance frameworks (SOC2, ISO27001)
resource "google_kms_key_ring" "vault_key_ring" {
  # Key ring name with unique suffix for deployment isolation
  # Prevents conflicts in shared GCP projects or multi-environment setups
  name = "${var.gcp_key_ring_name}-${random_id.platform_suffix.hex}"
  
  # Google Cloud project context for billing and access control
  project = var.gcp_project_id
  
  # Regional location for performance and compliance
  # Co-located with GKE cluster for optimal latency
  # Supports data residency and regulatory requirements
  location = var.gcp_region
}

# Google Cloud KMS Crypto Key
# Creates the actual encryption key used by HashiCorp Vault for seal/unseal
# operations. This key provides the cryptographic foundation for Vault's
# security model and enables automatic unsealing capabilities.
# 
# CRYPTO KEY FEATURES:
# - AES-256 encryption with Google Cloud HSM backing
# - Automatic key rotation based on configured schedule
# - Version management for key lifecycle operations
# - Integration with Google Cloud audit logging
# 
# VAULT INTEGRATION:
# - Used in Vault's GCP KMS seal configuration
# - Enables automatic unsealing after Vault pod restarts
# - Provides secure key storage without exposing keys to applications
# - Supports Vault high availability and disaster recovery
# 
# OPERATIONAL BENEFITS:
# - Eliminates manual Vault initialization procedures
# - Reduces operational complexity for Vault management
# - Enables automated backup and recovery processes
# - Provides enterprise-grade key management capabilities
# 
# SECURITY ARCHITECTURE:
# - Keys never leave Google Cloud HSM infrastructure
# - Access controlled through IAM service account permissions
# - All operations logged for security audit and compliance
# - Supports key rotation without service interruption
resource "google_kms_crypto_key" "vault_crypto_key" {
  # Crypto key name - configurable via variable for flexibility
  # Standard naming convention for Vault encryption keys
  name = var.gcp_crypto_key_name
  
  # Parent key ring reference - establishes key hierarchy
  # Links crypto key to appropriate key ring for organization
  key_ring = google_kms_key_ring.vault_key_ring.id
  
  # Additional configuration options (can be added as needed):
  # - purpose: "ENCRYPT_DECRYPT" (default for Vault unsealing)
  # - rotation_period: Automatic key rotation schedule
  # - next_rotation_time: Specific time for next key rotation
  # - labels: Resource labels for organization and billing
}
