# iSCSI CSI Driver - Basic Setup for Talos Linux

resource "kubectl_manifest" "iscsi_csi_driver" {
  yaml_body = <<-EOT
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: iscsi.csi.k8s.io
spec:
  attachRequired: true
  podInfoOnMount: true
  volumeLifecycleModes:
    - Persistent
EOT
}

resource "kubectl_manifest" "iscsi_namespace" {
  yaml_body = <<-EOT
apiVersion: v1
kind: Namespace
metadata:
  name: iscsi-csi
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOT
}

resource "kubectl_manifest" "iscsi_controller_sa" {
  depends_on = [kubectl_manifest.iscsi_namespace]
  yaml_body  = <<-EOT
apiVersion: v1
kind: ServiceAccount
metadata:
  name: iscsi-csi-controller-sa
  namespace: iscsi-csi
EOT
}

resource "kubectl_manifest" "iscsi_node_sa" {
  depends_on = [kubectl_manifest.iscsi_namespace]
  yaml_body  = <<-EOT
apiVersion: v1
kind: ServiceAccount
metadata:
  name: iscsi-csi-node-sa
  namespace: iscsi-csi
EOT
}

resource "kubectl_manifest" "iscsi_provisioner_role" {
  yaml_body = <<-EOT
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: iscsi-external-provisioner-role
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
EOT
}

resource "kubectl_manifest" "iscsi_provisioner_binding" {
  depends_on = [
    kubectl_manifest.iscsi_controller_sa,
    kubectl_manifest.iscsi_provisioner_role
  ]
  yaml_body = <<-EOT
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: iscsi-csi-provisioner-binding
subjects:
  - kind: ServiceAccount
    name: iscsi-csi-controller-sa
    namespace: iscsi-csi
roleRef:
  kind: ClusterRole
  name: iscsi-external-provisioner-role
  apiGroup: rbac.authorization.k8s.io
EOT
}

resource "kubectl_manifest" "iscsi_attacher_role" {
  yaml_body = <<-EOT
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: iscsi-external-attacher-role
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments/status"]
    verbs: ["patch"]
EOT
}

resource "kubectl_manifest" "iscsi_attacher_binding" {
  depends_on = [
    kubectl_manifest.iscsi_controller_sa,
    kubectl_manifest.iscsi_attacher_role
  ]
  yaml_body = <<-EOT
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: iscsi-csi-attacher-binding
subjects:
  - kind: ServiceAccount
    name: iscsi-csi-controller-sa
    namespace: iscsi-csi
roleRef:
  kind: ClusterRole
  name: iscsi-external-attacher-role
  apiGroup: rbac.authorization.k8s.io
EOT
}

resource "kubectl_manifest" "iscsi_controller" {
  depends_on = [
    kubectl_manifest.iscsi_controller_sa,
    kubectl_manifest.iscsi_provisioner_binding,
    kubectl_manifest.iscsi_attacher_binding
  ]
  wait = false
  yaml_body = <<-EOT
apiVersion: apps/v1
kind: Deployment
metadata:
  name: iscsi-csi-controller
  namespace: iscsi-csi
spec:
  replicas: 1
  selector:
    matchLabels:
      app: iscsi-csi-controller
  template:
    metadata:
      labels:
        app: iscsi-csi-controller
    spec:
      serviceAccountName: iscsi-csi-controller-sa
      containers:
        - name: csi-provisioner
          image: registry.k8s.io/sig-storage/csi-provisioner:v3.6.0
          args:
            - "--csi-address=/csi/csi.sock"
            - "--v=5"
            - "--timeout=30s"
            - "--leader-election=true"
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
        - name: csi-attacher
          image: registry.k8s.io/sig-storage/csi-attacher:v4.4.0
          args:
            - "--csi-address=/csi/csi.sock"
            - "--v=5"
            - "--timeout=30s"
            - "--leader-election=true"
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
        - name: iscsi-driver
          image: gcr.io/k8s-staging-sig-storage/iscsiplugin:v0.1.0
          args:
            - "--endpoint=unix:///csi/csi.sock"
            - "--nodeid=$(NODE_ID)"
            - "--v=5"
          env:
            - name: NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
          volumeMounts:
            - name: socket-dir
              mountPath: /csi
      volumes:
        - name: socket-dir
          emptyDir: {}
EOT
}

resource "kubectl_manifest" "iscsi_node" {
  depends_on = [
    kubectl_manifest.iscsi_node_sa
  ]
  wait = false
  yaml_body = <<-EOT
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iscsi-csi-node
  namespace: iscsi-csi
spec:
  selector:
    matchLabels:
      app: iscsi-csi-node
  template:
    metadata:
      labels:
        app: iscsi-csi-node
    spec:
      serviceAccountName: iscsi-csi-node-sa
      hostNetwork: true
      hostPID: true
      containers:
        - name: node-driver-registrar
          image: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.9.0
          args:
            - "--csi-address=/csi/csi.sock"
            - "--kubelet-registration-path=/var/lib/kubelet/plugins/iscsi.csi.k8s.io/csi.sock"
            - "--v=5"
          volumeMounts:
            - name: plugin-dir
              mountPath: /csi
            - name: registration-dir
              mountPath: /registration
        - name: iscsi-driver
          image: gcr.io/k8s-staging-sig-storage/iscsiplugin:v0.1.0
          args:
            - "--endpoint=unix:///csi/csi.sock"
            - "--nodeid=$(NODE_ID)"
            - "--v=5"
          env:
            - name: NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
            allowPrivilegeEscalation: true
          volumeMounts:
            - name: plugin-dir
              mountPath: /csi
            - name: pods-mount-dir
              mountPath: /var/lib/kubelet/pods
              mountPropagation: Bidirectional
            - name: device-dir
              mountPath: /dev
            - name: iscsi-dir
              mountPath: /etc/iscsi
            - name: host-sys
              mountPath: /sys
            - name: lib-modules
              mountPath: /lib/modules
              readOnly: true
      volumes:
        - name: plugin-dir
          hostPath:
            path: /var/lib/kubelet/plugins/iscsi.csi.k8s.io/
            type: DirectoryOrCreate
        - name: registration-dir
          hostPath:
            path: /var/lib/kubelet/plugins_registry/
            type: Directory
        - name: pods-mount-dir
          hostPath:
            path: /var/lib/kubelet/pods
            type: Directory
        - name: device-dir
          hostPath:
            path: /dev
            type: Directory
        - name: iscsi-dir
          hostPath:
            path: /etc/iscsi
            type: DirectoryOrCreate
        - name: host-sys
          hostPath:
            path: /sys
            type: Directory
        - name: lib-modules
          hostPath:
            path: /lib/modules
            type: Directory
EOT
}

resource "kubectl_manifest" "iscsi_storage_class" {
  depends_on = [
    kubectl_manifest.iscsi_csi_driver,
    kubectl_manifest.iscsi_controller,
    kubectl_manifest.iscsi_node
  ]
  
  yaml_body = <<-EOT
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: iscsi-csi
provisioner: iscsi.csi.k8s.io
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: false
EOT
}