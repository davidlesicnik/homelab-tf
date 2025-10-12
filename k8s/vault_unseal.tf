# After you initialize Vault and get your unseal keys, create this secret manually:
# kubectl create secret generic vault-unseal-keys -n vault \
#   --from-literal=key1='<unseal-key-1>' \
#   --from-literal=key2='<unseal-key-2>' \
#   --from-literal=key3='<unseal-key-3>'

resource "kubernetes_service_account" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
}

resource "kubernetes_role" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vault_unseal.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_unseal.metadata[0].name
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
}

resource "kubectl_manifest" "vault_unseal_cronjob" {
  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: CronJob
    metadata:
      name: vault-auto-unseal
      namespace: ${kubernetes_namespace.vault.metadata[0].name}
    spec:
      schedule: "*/5 * * * *"
      jobTemplate:
        spec:
          template:
            spec:
              serviceAccountName: ${kubernetes_service_account.vault_unseal.metadata[0].name}
              restartPolicy: OnFailure
              containers:
              - name: unseal
                image: bitnami/kubectl:latest
                command: ["/bin/bash", "-c"]
                args:
                - |
                  # Check if vault is sealed (exit code 2 means sealed)
                  if ! kubectl exec -n vault vault-0 -- vault status > /dev/null 2>&1; then
                    echo "Vault is sealed, unsealing..."
                    kubectl exec -n vault vault-0 -- vault operator unseal $KEY1
                    kubectl exec -n vault vault-0 -- vault operator unseal $KEY2
                    kubectl exec -n vault vault-0 -- vault operator unseal $KEY3
                    echo "Unseal complete"
                  else
                    echo "Vault is already unsealed"
                  fi
                env:
                - name: KEY1
                  valueFrom:
                    secretKeyRef:
                      name: vault-unseal-keys
                      key: key1
                - name: KEY2
                  valueFrom:
                    secretKeyRef:
                      name: vault-unseal-keys
                      key: key2
                - name: KEY3
                  valueFrom:
                    secretKeyRef:
                      name: vault-unseal-keys
                      key: key3
  YAML

  depends_on = [
    helm_release.vault,
    kubernetes_role_binding.vault_unseal
  ]
}