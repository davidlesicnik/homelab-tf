# Remove the exclude-from-external-load-balancers label from all nodes
resource "null_resource" "remove_node_label" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl get nodes -o name | xargs -I {} kubectl label {} node.kubernetes.io/exclude-from-external-load-balancers-
    EOT
  }

  # Optionally add a trigger to re-run if needed
  triggers = {
    always_run = timestamp()
  }
}

resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
  
  depends_on = [null_resource.remove_node_label]
}

resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = kubernetes_namespace.metallb_system.metadata[0].name
  version    = var.metallb_chart_version
  depends_on = [kubernetes_namespace.metallb_system]
}

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
  depends_on = [helm_release.metallb]
}

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
  depends_on = [kubectl_manifest.metallb_ipaddresspool]
}