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
  
  wait          = true
  wait_for_jobs = true
  timeout       = 600
  
  values = [
    yamlencode({
      defaultSettings = {
        defaultDataPath = "/var/lib/longhorn"
       
        defaultReplicaCount                = 2
        replicaSoftAntiAffinity           = "true"
        replicaAutoBalance                = "best-effort"
        storageMinimalAvailablePercentage = 10
       
        createDefaultDiskLabeledNodes = true
       
        guaranteedEngineManagerCPU    = 12
        guaranteedReplicaManagerCPU   = 12
        
        # Backup configuration
        backupTarget = "nfs://192.168.10.9:/volume1/longhorn_backup"
        backupTargetCredentialSecret = ""  # Leave empty if no authentication needed
      }
     
      persistence = {
        defaultClass             = true
        defaultClassReplicaCount = 2
        reclaimPolicy            = "Delete"
      }
      
      ingress = {
        enabled = false
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
  
  depends_on = [helm_release.longhorn]
}

# Label Talos nodes for Longhorn automatic disk creation
resource "kubernetes_labels" "longhorn_disk_label" {
  for_each = toset(var.longhorn_nodes)
  
  api_version = "v1"
  kind        = "Node"
  
  metadata {
    name = each.key
  }
  
  labels = {
    "node.longhorn.io/create-default-disk" = "true"
  }
  
  depends_on = [helm_release.longhorn]
}

# Recurring backup job - runs every 6 hours for all volumes
resource "kubernetes_manifest" "longhorn_recurring_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    
    metadata = {
      name      = "backup-every-6h"
      namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    
    spec = {
      name = "backup-every-6h"
      task = "backup"
      cron = "0 */6 * * *"  # Every 6 hours at minute 0
      retain = 14            # Keep 14 backups (3.5 days worth)
      concurrency = 2        # Run 2 backup jobs concurrently
      labels = {
        "schedule" = "every-6h"
      }
    }
  }
  
  depends_on = [helm_release.longhorn]
}

# Apply the recurring job to all volumes by default
resource "kubernetes_manifest" "longhorn_default_recurring_jobs" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "Setting"
    
    metadata = {
      name      = "recurring-job-selector"
      namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    
    value = jsonencode([
      {
        name    = "backup-every-6h"
        isGroup = false
      }
    ])
  }
  
  depends_on = [
    helm_release.longhorn,
    kubernetes_manifest.longhorn_recurring_backup
  ]
}