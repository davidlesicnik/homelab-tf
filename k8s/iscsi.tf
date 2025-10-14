resource "kubectl_manifest" "iscsi_csi_driver" {
  yaml_body = <<-EOT
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iscsi-csi-node
  namespace: kube-system
  labels:
    app: iscsi-csi
spec:
  selector:
    matchLabels:
      app: iscsi-csi
  template:
    metadata:
      labels:
        app: iscsi-csi
    spec:
      containers:
        - name: iscsi-csi-driver
          image: quay.io/k8scsi/iscsiplugin:v1.2.0
          args:
            - "--nodeid=$(NODE_NAME)"
          env:
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          securityContext:
            privileged: true
          volumeMounts:
            - name: dev
              mountPath: /dev
            - name: pods-mount
              mountPath: /var/lib/kubelet/pods
            - name: registration
              mountPath: /registration
      volumes:
        - name: dev
          hostPath:
            path: /dev
        - name: pods-mount
          hostPath:
            path: /var/lib/kubelet/pods
        - name: registration
          hostPath:
            path: /registration
EOT
}

resource "kubernetes_storage_class" "iscsi" {
  metadata {
    name = "iscsi-storage-class"
  }

  storage_provisioner = "csi.iscsi"  # CSI driver provisioner
  parameters = {
    targetPortal = var.iscsi_target_ip
    iqn          = var.iscsi_target_iqn
    lun          = var.iscsi_lun
    fsType       = var.iscsi_fs_type
  }

  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
}
