resource "kubernetes_storage_class" "iscsi" {
  metadata {
    name = "iscsi-storage-class"
  }

  storage_provisioner = "kubernetes.io/iscsi"
  parameters = {
    targetPortal = var.iscsi_target_ip
    iqn          = var.iscsi_target_iqn
    lun          = var.iscsi_lun
    fsType       = var.iscsi_fs_type
    readOnly     = "false"
  }

  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}
