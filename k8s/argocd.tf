resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_chart_version
  
  values = [
    yamlencode({
      global = {
        domain = "argocd.local"
      }
      
      server = {
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
          hosts = [{
            host  = "argocd.local"
            paths = [{ path = "/", pathType = "Prefix" }]
          }]
        }
      }
      
      configs = {
        params = {
          "server.url"      = "http://argocd.local"
          "server.insecure" = "true"
        }
        repositories = {
          homelab-repo = {
            url  = "https://github.com/davidlesicnik/homelab-argo"
            type = "git"
          }
        }
      }
      
      # Root Application (App of Apps)
      applications = {
        root = {
          enabled = true
          source = {
            repoURL        = "https://github.com/davidlesicnik/homelab-argo"
            targetRevision = "master"
            path           = "apps"  # Adjust this path to where your app manifests are
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = [
              "CreateNamespace=true"
            ]
          }
        }
      }
    })
  ]
  
  depends_on = [
    kubernetes_namespace.argocd,
    helm_release.nginx_ingress,
    kubectl_manifest.metallb_l2advertisement
  ]
}