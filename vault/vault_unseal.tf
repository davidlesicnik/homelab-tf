# vault_unseal.tf

# This data block fetches the existing 'vault' namespace so other resources can use it.
data "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"
  }
}

# Creates a Service Account for the unseal CronJob to use.
resource "kubernetes_service_account" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = data.kubernetes_namespace.vault.metadata[0].name
  }
}

# Creates a Role with the specific permissions needed to find and exec into the Vault pod.
resource "kubernetes_role" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = data.kubernetes_namespace.vault.metadata[0].name
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

# Binds the Role to the Service Account, granting it the necessary permissions.
resource "kubernetes_role_binding" "vault_unseal" {
  metadata {
    name      = "vault-unseal"
    namespace = data.kubernetes_namespace.vault.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vault_unseal.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_unseal.metadata[0].name
    namespace = data.kubernetes_namespace.vault.metadata[0].name
  }
}

# Defines the CronJob that runs every 5 minutes to check and unseal Vault.
resource "kubectl_manifest" "vault_unseal_cronjob" {
  yaml_body = <<-YAML
    apiVersion: batch/v1
    kind: CronJob
    metadata:
      name: vault-auto-unseal
      namespace: ${data.kubernetes_namespace.vault.metadata[0].name}
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
                  # Find any running vault pod, not just vault-0
                  VAULT_POD=$(kubectl get pod -n vault -l app.kubernetes.io/name=vault -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | cut -d' ' -f1)
                  if [ -z "$VAULT_POD" ]; then
                    echo "No running vault pod found."
                    exit 1
                  fi
                  # Check if vault is sealed (exit code 2 means sealed)
                  if ! kubectl exec -n vault $VAULT_POD -- vault status > /dev/null 2>&1; then
                    echo "Vault is sealed, unsealing..."
                    kubectl exec -n vault $VAULT_POD -- vault operator unseal $KEY1
                    kubectl exec -n vault $VAULT_POD -- vault operator unseal $KEY2
                    kubectl exec -n vault $VAULT_POD -- vault operator unseal $KEY3
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
    kubernetes_role_binding.vault_unseal
  ]
}