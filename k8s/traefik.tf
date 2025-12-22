resource "kubernetes_namespace" "traefik" {
  metadata {
    name = "traefik"
  }
}

# Install Gateway API CRDs
resource "kubectl_manifest" "gateway_api_crds" {
  for_each = toset([
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
  ])

  yaml_body = data.http.gateway_api_crds[each.key].response_body

  depends_on = [
    kubernetes_namespace.traefik
  ]
}

data "http" "gateway_api_crds" {
  for_each = toset([
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
  ])

  url = each.key
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = kubernetes_namespace.traefik.metadata[0].name
  version    = var.traefik_chart_version

  values = [
    yamlencode({
      # Enable Gateway API provider
      providers = {
        kubernetesGateway = {
          enabled = true
        }
      }

      # Disable the chart's built-in Gateway resource (we create our own)
      gateway = {
        enabled = false
      }

      # Service configuration - MetalLB will assign an IP from the pool
      service = {
        type = "LoadBalancer"
      }

      # Enable access logs for CrowdSec
      logs = {
        access = {
          enabled = true
          format  = "json"
          filePath = "/var/log/traefik/access.log"
        }
      }

      # Persistence for access logs (hostPath - shared with CrowdSec)
      persistence = {
        enabled = true
        name    = "traefik-logs"
        path    = "/var/log/traefik"
        type    = "hostPath"
      }

      # Ports configuration
      ports = {
        web = {
          port = 80
        }
        websecure = {
          port = 443
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.traefik,
    kubectl_manifest.metallb_l2advertisement,
    kubectl_manifest.gateway_api_crds
  ]
}

# Create a Gateway resource for applications to use
resource "kubectl_manifest" "traefik_gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: traefik-gateway
      namespace: traefik
    spec:
      gatewayClassName: traefik
      listeners:
      - name: http
        protocol: HTTP
        port: 80
        allowedRoutes:
          namespaces:
            from: All
      - name: https
        protocol: HTTPS
        port: 443
        allowedRoutes:
          namespaces:
            from: All
        tls:
          mode: Terminate
          certificateRefs:
          - kind: Secret
            name: default-tls-cert
  YAML

  depends_on = [
    helm_release.traefik
  ]
}
