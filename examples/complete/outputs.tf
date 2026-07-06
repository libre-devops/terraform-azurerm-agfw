output "agw_id" {
  description = "Resource id of the application gateway."
  value       = module.agfw.id
}

output "backend_pool_ids_zipmap" {
  description = "Backend pool name to { name, id }."
  value       = module.agfw.backend_pool_ids_zipmap
}

output "frontend_ip_configurations" {
  description = "Frontend configurations as returned by Azure."
  value       = module.agfw.frontend_ip_configurations
}

output "private_frontend_ip_address" {
  description = "Static private frontend ip."
  value       = module.agfw.private_frontend_ip_address
}

output "waf_policy_id" {
  description = "Resource id of the WAF policy."
  value       = module.agfw.waf_policy_id
}
