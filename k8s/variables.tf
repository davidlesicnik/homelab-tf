variable "metallb_chart_version" {
  type        = string
  default     = "0.14.5"
  description = "Version of the MetalLB Helm chart to deploy."
}

variable "nginx_ingress_chart_version" {
  type        = string
  default     = "4.10.1"
  description = "Version of the Nginx Ingress Helm chart to deploy."
}

variable "argocd_chart_version" {
  type        = string
  description = "Version of the Argo CD Helm chart to deploy."
  default     = "5.51.5"
}

variable "external_secrets_chart_version" {
  type        = string
  default     = "0.9.1"
  description = "Version of the External Secrets Helm chart to deploy."
}

variable "nfs_provisioner_chart_version" {
  type        = string
  default     = "4.0.18"
  description = "Version of the NFS provisioner Helm chart."
}

variable "metallb_ip_range" {
  type    = string
  default = "192.168.10.90-192.168.10.99"
}

variable "nfs_server_ip" {
  type        = string
  default     = "192.168.10.9"
  description = "IP address of the NFS server."
}

variable "nfs_server_path_ssd" {
  type        = string
  default     = "/volume2/ssd"
}

variable "nfs_server_path_hdd" {
  type        = string
  default     = "/volume1/hdd"
}

variable "nfs_server_path_media" {
  type        = string
  default     = "/volume1/media"
}
