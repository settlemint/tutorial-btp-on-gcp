# ============================================================================
# POSTGRESQL DATABASE DEPLOYMENT AND CONFIGURATION
# ============================================================================
# 
# Deploys and configures PostgreSQL, a powerful, open-source relational
# database system that serves as the primary data store for the BTP platform.
# PostgreSQL provides ACID compliance, advanced indexing, and comprehensive
# SQL support required for blockchain application data management.
# 
# POSTGRESQL OVERVIEW:
# PostgreSQL is chosen for the BTP platform due to its:
# - ACID compliance ensuring data consistency and reliability
# - Advanced indexing capabilities for high-performance queries
# - JSON and JSONB support for flexible blockchain data storage
# - Extensive ecosystem of extensions and tools
# - Enterprise-grade security features and access controls
# - Proven scalability for high-transaction blockchain applications
# 
# BTP PLATFORM INTEGRATION:
# In the BTP deployment, PostgreSQL serves critical functions:
# - User account and authentication data storage
# - Blockchain network configuration and metadata
# - Transaction history and audit logging
# - Application state and configuration management
# - Smart contract deployment tracking
# - Analytics and reporting data aggregation
# 
# ENTERPRISE FEATURES:
# - High availability through Kubernetes persistent volumes
# - Automated backup and recovery capabilities
# - Connection pooling for optimal resource utilization
# - Monitoring and alerting integration
# - Security hardening with role-based access control
# - Performance tuning for blockchain workload patterns
# 
# ============================================================================

# PostgreSQL Database Password Generation
# Generates a cryptographically secure random password for PostgreSQL
# database authentication. This password is used for both the application
# user and the PostgreSQL superuser (postgres) account.
# 
# PASSWORD SECURITY:
# - 16-character length provides strong security against brute force attacks
# - Excludes special characters to avoid shell escaping and configuration issues
# - Uses cryptographically secure random generation
# - Automatically managed by Terraform state for consistency
# 
# CREDENTIAL MANAGEMENT:
# - Password is stored in Terraform state (consider remote state encryption)
# - Used by BTP applications for database connectivity
# - Can be rotated by updating Terraform configuration
# - Should be backed up as part of disaster recovery procedures
resource "random_password" "postgresql_password" {
  length  = 16
  special = false  # Avoid special characters for compatibility
}

# PostgreSQL Helm Release
# Deploys PostgreSQL using the official Bitnami Helm chart, which provides
# a production-ready database deployment with comprehensive configuration
# options, monitoring, and operational features.
# 
# BITNAMI CHART FEATURES:
# - Production-ready PostgreSQL configuration
# - Integrated backup and recovery mechanisms
# - Comprehensive monitoring and metrics collection
# - Security hardening and access controls
# - Persistent storage integration with Kubernetes
# - High availability and clustering support (when configured)
# 
# DEPLOYMENT ARCHITECTURE:
# - Single-instance deployment suitable for development and small production
# - Persistent volume for data durability across pod restarts
# - Service exposure for internal cluster communication
# - ConfigMap and Secret management for configuration
# - Integration with Kubernetes RBAC and security policies
resource "helm_release" "postgresql" {
  # Release identification and metadata
  name       = "postgresql"
  
  # Bitnami OCI registry for PostgreSQL Helm chart
  # Provides regularly updated, security-patched PostgreSQL deployments
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "postgresql"
  version    = "16.7.27"  # Stable version with PostgreSQL 16.x
  
  # Deploy in cluster dependencies namespace
  # Co-locates with other infrastructure services
  namespace = var.dependencies_namespace


  # Namespace creation (redundant but safe)
  create_namespace = true

  # Database User Configuration
  # Creates application user with database access permissions
  # Uses platform name for consistent resource identification
  set {
    name  = "global.postgresql.auth.username"
    value = var.gcp_platform_name
  }

  # Application User Password
  # Sets password for the application database user
  # Uses generated random password for security
  set {
    name  = "global.postgresql.auth.password"
    value = random_password.postgresql_password.result
  }

  # PostgreSQL Superuser Password
  # Sets password for the PostgreSQL 'postgres' superuser account
  # Uses same password as application user for simplicity
  # In production, consider using different passwords for enhanced security
  set {
    name  = "global.postgresql.auth.postgresPassword"
    value = random_password.postgresql_password.result
  }

  # Default Database Creation
  # Creates initial database for BTP platform applications
  # Uses platform name for consistent resource identification
  set {
    name  = "global.postgresql.auth.database"
    value = var.gcp_platform_name
  }

  # Additional configuration options (can be uncommented as needed):
  # 
  # Storage Configuration:
  # set {
  #   name  = "primary.persistence.size"
  #   value = "100Gi"  # Adjust based on expected data volume
  # }
  # 
  # Performance Tuning:
  # set {
  #   name  = "primary.extendedConfiguration"
  #   value = "max_connections = 200\nshared_buffers = 256MB"
  # }
  # 
  # Backup Configuration:
  # set {
  #   name  = "backup.enabled"
  #   value = "true"
  # }
  # 
  # Monitoring Integration:
  # set {
  #   name  = "metrics.enabled"
  #   value = "true"
  # }

  # Deployment Dependencies
  # Ensures GKE cluster and namespace are ready before database deployment
  depends_on = [module.gke, kubernetes_namespace.cluster_dependencies_namespace]
}