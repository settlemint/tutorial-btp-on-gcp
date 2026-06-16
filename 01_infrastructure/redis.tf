# ============================================================================
# REDIS CACHE DEPLOYMENT AND CONFIGURATION
# ============================================================================
# 
# Deploys and configures Redis, a high-performance in-memory data structure
# store that serves as the primary caching and session storage solution for
# the BTP platform. Redis provides sub-millisecond response times and
# advanced data structures essential for blockchain application performance.
# 
# REDIS OVERVIEW:
# Redis is chosen for the BTP platform due to its:
# - Exceptional performance with sub-millisecond response times
# - Rich data structures (strings, hashes, lists, sets, sorted sets)
# - Built-in pub/sub messaging for real-time blockchain event handling
# - Atomic operations ensuring data consistency in concurrent environments
# - Lua scripting support for complex blockchain data processing
# - Persistence options for durability and disaster recovery
# 
# BTP PLATFORM INTEGRATION:
# In the BTP deployment, Redis serves critical functions:
# - Session storage for user authentication and state management
# - Caching of frequently accessed blockchain data and metadata
# - Real-time event streaming for blockchain transaction notifications
# - Rate limiting and throttling for API endpoints
# - Temporary storage for blockchain node synchronization data
# - Message queuing for asynchronous blockchain operations
# 
# ENTERPRISE FEATURES:
# - High availability through master-replica configurations (when configured)
# - Automatic failover and cluster management capabilities
# - Comprehensive monitoring and alerting integration
# - Security hardening with authentication and encryption
# - Backup and restore mechanisms for data protection
# - Performance optimization for blockchain workload patterns
# 
# ============================================================================

# Redis Authentication Password Generation
# Generates a cryptographically secure random password for Redis
# authentication. This password protects the Redis instance from
# unauthorized access and ensures secure communication between
# BTP applications and the Redis service.
# 
# PASSWORD SECURITY:
# - 16-character length provides strong security against brute force attacks
# - Excludes special characters to avoid configuration and client library issues
# - Uses cryptographically secure random generation
# - Automatically managed by Terraform state for consistency
# 
# CREDENTIAL MANAGEMENT:
# - Password is used by all BTP applications for Redis connectivity
# - Stored in Kubernetes secrets for secure access
# - Can be rotated by updating Terraform configuration
# - Should be included in disaster recovery backup procedures
resource "random_password" "redis_password" {
  length  = 16
  special = false  # Avoid special characters for client compatibility
}

# Redis Helm Release
# Deploys Redis using the official Bitnami Helm chart, which provides
# a production-ready Redis deployment with comprehensive configuration
# options, monitoring, and operational features.
# 
# BITNAMI CHART FEATURES:
# - Production-ready Redis configuration with security hardening
# - Multiple deployment architectures (standalone, master-replica, cluster)
# - Integrated monitoring and metrics collection
# - Persistent storage options for data durability
# - Comprehensive backup and recovery mechanisms
# - Security features including TLS encryption and authentication
# 
# DEPLOYMENT ARCHITECTURE:
# - Standalone deployment suitable for development and small production
# - Single Redis instance with persistent storage
# - Service exposure for internal cluster communication
# - ConfigMap and Secret management for configuration
# - Integration with Kubernetes resource management and scaling
resource "helm_release" "redis" {
  # Release identification and metadata
  name       = "redis"
  
  # Bitnami OCI registry for Redis Helm chart
  # Provides regularly updated, security-patched Redis deployments
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "redis"
  version    = "25.5.3"  # Stable version with Redis 7.x
  
  # Deploy in cluster dependencies namespace
  # Co-locates with other infrastructure services
  namespace = var.dependencies_namespace

  # Namespace creation (redundant but safe)
  create_namespace = true

  # Redis Architecture Configuration
  # Standalone mode provides single Redis instance
  # Suitable for development and small production deployments
  # For high availability, consider "replication" mode with master-replica setup
  set {
    name  = "architecture"
    value = "standalone"
  }

  # Redis Authentication Configuration
  # Enables password-based authentication for security
  # Uses generated random password for strong access control
  set {
    name  = "global.redis.password"
    value = random_password.redis_password.result
  }

  # Additional configuration options (can be uncommented as needed):
  # 
  # High Availability Configuration:
  # set {
  #   name  = "architecture"
  #   value = "replication"  # Enable master-replica setup
  # }
  # 
  # Persistence Configuration:
  # set {
  #   name  = "master.persistence.enabled"
  #   value = "true"
  # }
  # set {
  #   name  = "master.persistence.size"
  #   value = "50Gi"  # Adjust based on expected data volume
  # }
  # 
  # Performance Tuning:
  # set {
  #   name  = "master.resources.requests.memory"
  #   value = "1Gi"
  # }
  # set {
  #   name  = "master.resources.requests.cpu"
  #   value = "500m"
  # }
  # 
  # Security Configuration:
  # set {
  #   name  = "auth.enabled"
  #   value = "true"
  # }
  # set {
  #   name  = "tls.enabled"
  #   value = "true"  # Enable TLS encryption
  # }
  # 
  # Monitoring Integration:
  # set {
  #   name  = "metrics.enabled"
  #   value = "true"
  # }

  # Deployment Dependencies
  # Ensures GKE cluster and namespace are ready before Redis deployment
  depends_on = [module.gke, kubernetes_namespace.cluster_dependencies_namespace]
}