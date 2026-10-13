output "quote_api_record" {
  description = "the adopted record, name + proxied flag"
  value = {
    name    = cloudflare_dns_record.quote_api.name
    proxied = cloudflare_dns_record.quote_api.proxied
  }
}

output "id_after_import" {
  description = "resource id used in the import operation (for runbook checks)"
  value       = cloudflare_dns_record.quote_api.id
}
