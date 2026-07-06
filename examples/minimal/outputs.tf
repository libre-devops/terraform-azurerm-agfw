output "agw_id" {
  description = "Resource id of the application gateway."
  value       = module.agfw.id
}

output "waf_policy_id" {
  description = "Resource id of the auto-created WAF policy."
  value       = module.agfw.waf_policy_id
}
