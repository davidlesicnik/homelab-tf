# providers.tf

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

provider "vault" {
  address = "http://vault.local"
  token   = var.vault_root_token
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "kubectl" {
  config_path = "~/.kube/config"
}
