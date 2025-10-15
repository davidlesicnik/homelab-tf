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
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      server = {
        insecure = true
        extraArgs = ["--insecure"]
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          hosts = ["argocd.local"]
          paths = ["/"]
          annotations = {
            "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
            "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
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

# Give ArgoCD time to fully initialize after Helm installation
resource "time_sleep" "wait_for_argocd" {
  create_duration = "60s"
  depends_on      = [helm_release.argocd]
}

# Wait for ArgoCD to fully initialize and CRDs to be established
resource "terraform_data" "argocd_ready" {
  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for ArgoCD CRDs to be established..."
      kubectl wait --for=condition=established --timeout=300s \
        crd/applications.argoproj.io \
        crd/applicationsets.argoproj.io
      
      echo "Waiting for default AppProject..."
      until kubectl get appproject default -n argocd 2>/dev/null; do
        echo "Still waiting for default AppProject..."
        sleep 5
      done
      echo "ArgoCD is ready!"
    EOF
  }

  depends_on = [time_sleep.wait_for_argocd]
}

# Create the root Application
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
 
  depends_on = [
    terraform_data.argocd_ready
  ]
}