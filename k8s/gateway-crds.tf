# Install Gateway API CRDs
resource "kubectl_manifest" "gateway_api_crds" {
  for_each = toset([
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml"
  ])

  yaml_body = data.http.gateway_api_crds[each.key].response_body
}

data "http" "gateway_api_crds" {
  for_each = toset([
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml"
  ])

  url = each.key
}
