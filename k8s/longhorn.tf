# Longhorn namespace
resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# Longhorn Helm release
resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = var.longhorn_chart_version
  namespace  = kubernetes_namespace.longhorn_system.metadata[0].name

  # Wait for CRDs and resources to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      defaultSettings = {
        # CRITICAL: Point to your persistent mount
        defaultDataPath = "/var/lib/longhorn"
        
        defaultReplicaCount                = 1
        replicaSoftAntiAffinity           = "false"
        replicaAutoBalance                = "disabled"
        storageMinimalAvailablePercentage = 10
        
        # Talos-specific: Ensure proper directory creation
        createDefaultDiskLabeledNodes = true
        
        # Optional: Adjust based on your needs
        guaranteedEngineManagerCPU    = 12
        guaranteedReplicaManagerCPU   = 12
      }
     
      # Persistence settings
      persistence = {
        defaultClass             = true
        defaultClassReplicaCount = 1
        reclaimPolicy            = "Delete"
      }

      # Ingress configuration
      ingress = {
        enabled = false
        # We're creating a separate ingress resource instead
      }

      # Resource limits
      longhornManager = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
        tolerations = []
      }

      longhornDriver = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      longhornUI = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.longhorn_system]
}

# Longhorn UI Ingress
resource "kubernetes_ingress_v1" "longhorn" {
  metadata {
    name      = "longhorn-ingress"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size" = "10000m"
      # Optional: Add basic auth for security
      # "nginx.ingress.kubernetes.io/auth-type" = "basic"
      # "nginx.ingress.kubernetes.io/auth-secret" = "longhorn-basic-auth"
      # "nginx.ingress.kubernetes.io/auth-realm" = "Authentication Required"
    }
  }

  spec {
    ingress_class_name = "nginx"
    
    rule {
      host = "longhorn.local"
      
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          
          backend {
            service {
              name = "longhorn-frontend"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.longhorn
  ]
}

# Optional: Custom StorageClass (remove if you prefer Longhorn's default)
resource "kubernetes_storage_class" "longhorn" {
  metadata {
    name = "longhorn"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "driver.longhorn.io"
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"

  parameters = {
    numberOfReplicas    = "1"
    staleReplicaTimeout = "30"
    fromBackup          = ""
    fsType              = "ext4"
  }

  depends_on = [helm_release.longhorn]
}