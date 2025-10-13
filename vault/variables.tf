variable "kubernetes_host" {
  type        = string
  default     = "192.168.10.40"
  description = "The Kubernetes API server URL."
}

variable "vault_root_token" {
  type        = string
  description = "The root token for Vault."
  sensitive   = true
}