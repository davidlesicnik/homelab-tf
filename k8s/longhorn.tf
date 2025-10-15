# Longhorn namespace
resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
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
      # Default replica count for single node
      defaultSettings = {
        defaultReplicaCount        = 1
        replicaSoftAntiAffinity   = "false"
        replicaAutoBalance        = "disabled"
        storageMinimalAvailablePercentage = 10
        # Optional: Configure data path if needed
        # defaultDataPath = "/var/lib/longhorn"
      }
      
      # Persistence settings
      persistence = {
        defaultClass           = true
        defaultClassReplicaCount = 1
        reclaimPolicy         = "Delete"
      }

      # Ingress configuration (optional - for Longhorn UI)
      ingress = {
        enabled = false
        # Uncomment and configure if you want to expose the UI
        # host    = "longhorn.local"
        # ingressClassName = "nginx"
      }

      # Resource limits (adjust based on your node capacity)
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
}