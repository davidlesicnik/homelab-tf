resource "kubernetes_namespace" "nfs_provisioner" {
  metadata {
    name = "nfs-provisioner"
  }
}

resource "helm_release" "nfs-provisioner-ssd" {
  name       = "nfs-subdir-external-provisioner-ssd"
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
      storageClass = { name = "nfs-client-ssd" }
    })
  ]

  depends_on = [kubernetes_namespace.nfs_provisioner]
}

resource "helm_release" "nfs-provisioner-hdd" {
  name       = "nfs-subdir-external-provisioner-hdd"
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
      storageClass = { name = "nfs-client-hdd" }
    })
  ]

  depends_on = [kubernetes_namespace.nfs_provisioner]
}
