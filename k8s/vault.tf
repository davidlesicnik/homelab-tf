resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = kubernetes_namespace.vault.metadata[0].name
  version    = "0.28.0"

  values = [
    yamlencode({
      server = {
        standalone = {
          enabled = true
        }
        dataStorage = {
          enabled      = true
          size         = "10Gi"
          storageClass = "nfs-client-hdd"
        }
      }
      ui = {
        enabled = true
      }
      injector = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.vault,
    helm_release.nginx_ingress,
    kubectl_manifest.metallb_l2advertisement
  ]
}

output "vault_namespace" {
  value = kubernetes_namespace.vault.metadata[0].name
}

output "vault_init_command" {
  value = "kubectl exec -n ${kubernetes_namespace.vault.metadata[0].name} vault-0 -- vault operator init"
}