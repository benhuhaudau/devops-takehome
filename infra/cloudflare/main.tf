# 5b: Cloudflare for DNS/CDN, managed by Terraform.
# Provider: cloudflare/cloudflare ~> 5.x (resource used: cloudflare_zone,
# cloudflare_dns_record (the 5.x name; 4.x called it cloudflare_dns_record too:
# verified against current provider docs).
# The zone itself is pre-existing (unmanaged); only the records/rules are ours.

terraform {
  required_version = ">= 1.6"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token # no zone-level token in code
}

# ---------------------------------------------------------------- DNS record
resource "cloudflare_dns_record" "quote_api" {
  # 5.x renamed the resource (was cloudflare_dns_record in 4.x)
  zone_id = var.zone_id
  name    = "quote-api"
  type    = "CNAME"
  content = var.origin
  proxied = true # stays behind the Cloudflare edge
  ttl     = 1    # 1 = auto when proxied
  comment = "managed quote-api endpoint (origin not directly reachable)"
}

# ---------------------------------------------------------- cache controls
# /api/*  → cache bypass (dynamic inference endpoint; a cached "quote" is a bug)
# static assets → aggressive cache (604800s TTL) for LCP
resource "cloudflare_ruleset" "zone_cache_rules" {
  zone_id = var.zone_id
  name    = "quote-api-cache-rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      expression  = "(http.request.uri.path matches \"^/api/\")"
      action      = "set_cache_settings"
      description = "bypass cache for /api/*"
      enabled     = true
      action_parameters = {
        cache = false
      }
    },
    {
      expression  = "(http.request.uri.path matches \"\\.(?:css|js|png|jpg|jpeg|svg|woff2|ico)$\")"
      action      = "set_cache_settings"
      description = "cache static assets aggressively"
      enabled     = true
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 604800
        }
      }
    },
  ]
}

# -------------------------------------------------------------- import block
# We regularly adopt manually-created resources into Terraform. This models one:
# an existing quote-api record created by hand in the UI, later adopted via
# `import` (tf >= 1.5 applies it on the next plan). After a successful apply
# the block's id must be replaced by the real record id to stay a no-op for
# subsequent runs.
import {
  to = cloudflare_dns_record.quote_api
  id = "4c9a33ba22f9aa5242131a8f7e41f7f0"
}


