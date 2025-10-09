terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

# Configure the Kubernetes provider
# It will automatically use the kubeconfig file from your home directory
provider "kubernetes" {
    config_path = "~/.kube/config"
}

# Example: Create a new namespace to test the connection
resource "kubernetes_namespace" "example" {
  metadata {
    name = "my-terraform-namespace"
  }
}