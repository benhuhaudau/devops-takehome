variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone.DNS + Zone.Cache Rules edit scopes"
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Existing Cloudflare zone id (created manually, not here)"
  type        = string
}

variable "origin" {
  description = "Origin FQDN the record points at (e.g. quote-api-lb.acme.io)"
  type        = string
  default     = "quote-api-internal.acme-devops.example.io"
}
