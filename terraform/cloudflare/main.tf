locals {
  tunnel_hostnames = toset([
    "api",
    "api-dev",
    "s3",
    "s3-dev",
    "minio",
    "minio-dev",
    "dev",
    "admin",
    "admin-dev",
    "www",
  ])
}

# The existing tunnel is deliberately not recreated or migrated here. Terraform
# owns its DNS routes; Kubernetes owns its ingress config.
resource "cloudflare_dns_record" "tunnel" {
  for_each = local.tunnel_hostnames
  zone_id  = var.zone_id
  name     = "${each.value}.medha.dev"
  type     = "CNAME"
  content  = "${var.tunnel_id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
  comment  = "Managed by medha-infra"
}

resource "cloudflare_dns_record" "apex_tunnel" {
  zone_id = var.zone_id
  name    = "medha.dev"
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Managed by medha-infra"
}
