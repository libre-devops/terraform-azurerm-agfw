output "backend_address_pools" {
  description = "Backend address pools as returned by Azure (names and ids), for NIC association composition."
  value       = azurerm_application_gateway.this.backend_address_pool
}

output "backend_pool_ids_zipmap" {
  description = "Map of backend pool name to a { name, id } object."
  value       = { for p in azurerm_application_gateway.this.backend_address_pool : p.name => { name = p.name, id = p.id } }
}

output "frontend_ip_configurations" {
  description = "Frontend ip configurations as returned by Azure (names, ids, private ip when a private frontend exists)."
  value       = azurerm_application_gateway.this.frontend_ip_configuration
}

output "http_listener_ids" {
  description = "Map of listener name to its id."
  value       = { for l in azurerm_application_gateway.this.http_listener : l.name => l.id }
}

output "id" {
  description = "Resource id of the application gateway."
  value       = azurerm_application_gateway.this.id
}

output "identity" {
  description = "The gateway's managed identity block, when one is set."
  value       = try(azurerm_application_gateway.this.identity[0], null)
}

output "name" {
  description = "Name of the application gateway."
  value       = azurerm_application_gateway.this.name
}

output "private_endpoint_connections" {
  description = "Private endpoint connections on the gateway (populated when private link configurations are used)."
  value       = azurerm_application_gateway.this.private_endpoint_connection
}

output "private_frontend_ip_address" {
  description = "Static private ip of the private frontend (null when no private frontend)."
  value       = var.private_frontend != null ? var.private_frontend.private_ip_address : null
}

output "public_frontend_name" {
  description = "Name of the public frontend ip configuration (for composing listeners elsewhere)."
  value       = local.frontend_names.public
}

output "resource_group_name" {
  description = "Resource group name parsed from resource_group_id."
  value       = local.resource_group_name
}

output "subscription_id" {
  description = "Subscription id parsed from resource_group_id."
  value       = local.rg.subscription_id
}

output "tags" {
  description = "The tags applied to the gateway."
  value       = var.tags
}

output "waf_policy_id" {
  description = "Resource id of the associated WAF policy (module-created or bring-your-own; null on Standard_v2 without one)."
  value       = local.firewall_policy_id
}

output "waf_policy_name" {
  description = "Name of the module-created WAF policy (null when not created here)."
  value       = local.create_waf_policy ? azurerm_web_application_firewall_policy.this[0].name : null
}
