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
      # This sets the domain for the Ingress and other components
      global = {
        domain = "argocd.local"
      }

      server = {
        ingress = {
          enabled          = true
          ingressClassName = "nginx"
        }
      }

      configs = {
        params = {
          # This tells Argo CD what its public-facing URL is
          "server.url" = "http://argocd.local"
          # This is the key setting: it disables the automatic HTTPS redirect
          "server.insecure" = "true"
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

resource "kubectl_manifest" "root_app" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-applicationset
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: https://github.com/davidlesicnik/homelab-argo
        targetRevision: master
        path: apps
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  YAML

  # This is CRITICAL. It ensures Argo CD is fully installed
  # BEFORE Terraform tries to create an application in it.
  depends_on = [helm_release.argocd]
}