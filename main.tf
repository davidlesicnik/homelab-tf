# Terraform configuration for setting up my kubernetes cluster.
# Currently includes MetalLB, Nginx Ingress Controller, ArgoCD and NFS mount.

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

variable "nfs_provisioner_chart_version" {
  type        = string
  description = "Version of the nfs-subdir-external-provisioner Helm chart."
  default     = "4.0.18"
}

variable "metallb_ip_range" {
  type    = string
  default = "192.168.10.90-192.168.10.99"
}

variable "nfs_server_ip" {
  type        = string
  description = "IP address of the NFS server."
  default     = "192.168.10.20"
}

variable "nfs_server_path_ssd" {
  type        = string
  description = "The path on the NFS server to provision storage from."
  default     = "/mnt/storage/k8s"
}

variable "nfs_server_path_hdd" {
  type        = string
  description = "The path on the NFS server to provision storage from."
  default     = "/mnt/storage/k8s"
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
      global = {
        domain = "argocd.local"
      }
      server = {
        ingress = {
          enabled          = true
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
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    helm_release.nginx_ingress,
    kubectl_manifest.metallb_l2advertisement
  ]
}

# NFS Provisioner Namespace
resource "kubernetes_namespace" "nfs_provisioner" {
  metadata {
    name = "nfs-provisioner"
  }
}

# Install NFS Subdir External Provisioner for ssd storage
resource "helm_release" "nfs_provisioner" {
  name       = "nfs-subdir-external-provisioner_ssd"
  repository = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart      = "nfs-subdir-external-provisioner"
  namespace  = kubernetes_namespace.nfs_provisioner.metadata[0].name
  version    = var.nfs_provisioner_chart_version

  values = [
    yamlencode({
      nfs = {
        server = var.nfs_server_ip
        path   = var.nfs_server_path_ssd
      }
      storageClass = {
        # This will be the name of the StorageClass you use in your PVCs
        name = "nfs-client"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.nfs_provisioner
  ]
}

# Install NFS Subdir External Provisioner for HDD path
resource "helm_release" "nfs_provisioner" {
  name       = "nfs-subdir-external-provisioner_hdd"
  repository = "https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/"
  chart      = "nfs-subdir-external-provisioner"
  namespace  = kubernetes_namespace.nfs_provisioner.metadata[0].name
  version    = var.nfs_provisioner_chart_version

  values = [
    yamlencode({
      nfs = {
        server = var.nfs_server_ip
        path   = var.nfs_server_path_hdd
      }
      storageClass = {
        # This will be the name of the StorageClass you use in your PVCs
        name = "nfs-client"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.nfs_provisioner
  ]
}