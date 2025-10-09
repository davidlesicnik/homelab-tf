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

# MetalLB Namespace
resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
  }
}

# Install MetalLB using Helm
resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = kubernetes_namespace.metallb_system.metadata[0].name
  version    = "0.14.5"

  depends_on = [
    kubernetes_namespace.metallb_system
  ]
}

resource "kubernetes_manifest" "metallb_ipaddresspool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default-pool"
      namespace = kubernetes_namespace.metallb_system.metadata[0].name
    }
    spec = {
      addresses = [
        "192.168.10.90-192.168.10.99"  # Adjust this range for your environment
      ]
    }
  }

  depends_on = [
    helm_release.metallb
  ]
}

# MetalLB L2 Advertisement
resource "kubernetes_manifest" "metallb_l2advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default"
      namespace = kubernetes_namespace.metallb_system.metadata[0].name
    }
    spec = {
      ipAddressPools = [
        kubernetes_manifest.metallb_ipaddresspool.manifest.metadata.name
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.metallb_ipaddresspool
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
  version    = "4.10.1"

  depends_on = [
    kubernetes_namespace.ingress_nginx,
    kubernetes_manifest.metallb_l2advertisement
  ]
}