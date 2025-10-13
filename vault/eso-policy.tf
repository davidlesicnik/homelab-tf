# main.tf

# Data source to automatically fetch the K8s cluster's root CA certificate.
data "kubernetes_config_map_v1" "kube_root_ca" {
  metadata {
    name      = "kube-root-ca.crt"
    namespace = "kube-system"
  }
}

resource "kubernetes_service_account_v1" "vault_reviewer" {
  metadata {
    name      = "vault-token-reviewer"
    namespace = "default"
  }
}

resource "kubernetes_secret_v1" "vault_reviewer_token" {
  metadata {
    name      = "vault-token-reviewer-secret"
    namespace = kubernetes_service_account_v1.vault_reviewer.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.vault_reviewer.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "k8s_config" {
  backend              = vault_auth_backend.kubernetes.path
  kubernetes_host      = var.kubernetes_host
  # Use the automatically fetched CA certificate from the data source
  kubernetes_ca_cert   = data.kubernetes_config_map_v1.kube_root_ca.data["ca.crt"]
  token_reviewer_jwt   = kubernetes_secret_v1.vault_reviewer_token.data["token"]
  disable_local_ca_jwt = true

  depends_on = [vault_auth_backend.kubernetes]
}

resource "vault_policy" "eso_policy" {
  name   = "external-secrets-policy"
  policy = file("${path.module}/eso-policy.hcl")
}

resource "vault_kubernetes_auth_backend_role" "eso_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external-secrets"
  bound_service_account_names      = ["external-secrets"]
  bound_service_account_namespaces = ["external-secrets"]
  token_policies                   = [vault_policy.eso_policy.name]
  token_ttl                        = 3600 # 1 hour

  depends_on = [
    vault_kubernetes_auth_backend_config.k8s_config,
    vault_policy.eso_policy
  ]
}