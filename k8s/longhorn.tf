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
        defaultDataPath = "/var/lib/longhorn"
        
        defaultReplicaCount                = 1
        replicaSoftAntiAffinity           = "false"
        replicaAutoBalance                = "disabled"
        storageMinimalAvailablePercentage = 10
        
        # Talos-specific: Ensure proper directory creation
        createDefaultDiskLabeledNodes = true
        
        guaranteedEngineManagerCPU    = 12
        guaranteedReplicaManagerCPU   = 12
      }
     
      persistence = {
        defaultClass             = true
        defaultClassReplicaCount = 1
        reclaimPolicy            = "Delete"
      }

      ingress = {
        enabled = false
        # We're creating a separate ingress resource instead
      }

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