# Terraform configuration for setting up my kubernetes cluster.
# Currently includes MetalLB, Nginx Ingress Controller and ArgoCD.

variable "metallb_chart_version" {
  type        = string
  description = "Version of the MetalLB Helm chart to deploy."
  default     = "0.14.5"
}

variable "nginx_ingress_chart_version" {
  type        = string
  description = "Version of the Nginx Ingress Helm chart to deploy."
  default     = "4.10.1"
}

variable "argocd_chart_version" {
  type        = string
  description = "Version of the Argo CD Helm chart to deploy."
  default     = "7.6.12"
}

variable "metallb_ip_range" {
  type    = string
  default = "192.168.10.90-192.168.10.99"
}
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

# MetalLB Namespace
resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# Install MetalLB using Helm
resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = kubernetes_namespace.metallb_system.metadata[0].name
  version    = var.metallb_chart_version

  depends_on = [
    kubernetes_namespace.metallb_system
  ]
}

# MetalLB IP Address Pool
# IMPORTANT: Adjust this IP range to match your local network
resource "kubectl_manifest" "metallb_ipaddresspool" {
  yaml_body = <<-YAML
    apiVersion: metallb.io/v1beta1
    kind: IPAddressPool
    metadata:
      name: default-pool
      namespace: metallb-system
    spec:
      addresses:
      - ${var.metallb_ip_range}
  YAML

  depends_on = [
    helm_release.metallb
  ]
}

# MetalLB L2 Advertisement
resource "kubectl_manifest" "metallb_l2advertisement" {
  yaml_body = <<-YAML
    apiVersion: metallb.io/v1beta1
    kind: L2Advertisement
    metadata:
      name: default
      namespace: metallb-system
    spec:
      ipAddressPools:
      - default-pool
  YAML

  depends_on = [
    kubectl_manifest.metallb_ipaddresspool
  ]
}

# Ingress Nginx Namespace
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

# Install Nginx Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  version    = var.nginx_ingress_chart_version

  depends_on = [
    kubernetes_namespace.ingress_nginx,
    kubectl_manifest.metallb_l2advertisement
  ]
}

# Argo CD Namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

# Argo CD Helm Chart
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_chart_version

  values = [
    yamlencode({
      server = {
        service = {
          type = "ClusterIP"  # important: no LoadBalancer
        }
        ingress = {
          enabled = true
          ingressClassName = "nginx"
          hosts = [
            {
              host  = "argocd.local"
              paths = [
                {
                  path     = "/"
                  pathType = "Prefix"
                }
              ]
            }
          ]
          tls = [] # add TLS config if needed
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
