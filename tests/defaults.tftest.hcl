# Plan-time tests for the module. The provider is mocked, so no credentials, no features block,
# and no cloud calls are needed:
#   terraform init -backend=false && terraform test

mock_provider "azurerm" {}

variables {
  location             = "uksouth"
  resource_group_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01"
  name                 = "agw-ldo-uks-tst-01"
  gateway_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Network/virtualNetworks/vnet-ldo-uks-tst-01/subnets/snet-agw-vnet-ldo-uks-tst-01"
  public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Network/publicIPAddresses/pip-ldo-uks-tst-01"

  backend_pools = { "app" = { ip_addresses = ["10.0.2.10"] } }

  backend_http_settings = { "app-https" = {} }

  probes = { "app-health" = {} }

  ssl_certificates = {
    "wildcard" = { data = "bm90LWEtcmVhbC1wZng=", password = "not-a-real-password" }
  }

  listeners = {
    "web-https" = { port = 443, protocol = "Https", ssl_certificate_key = "wildcard" }
    "web-http"  = { port = 80, protocol = "Http" }
  }

  request_routing_rules = {
    "redirect" = { listener_key = "web-http", redirect_key = "to-https" }
    "web"      = { listener_key = "web-https", backend_pool_key = "app", backend_http_settings_key = "app-https", priority = 500 }
  }

  redirect_configurations = {
    "to-https" = { target_listener_key = "web-https" }
  }
}

# Secure defaults: WAF_v2 with an auto-created Prevention policy on DRS 2.1 + Bot Manager, TLS 1.2
# floor, zone redundancy, autoscale, http2, and the derived plumbing.
run "secure_defaults" {
  command = plan

  expect_failures = [check.listeners_prefer_tls]

  assert {
    condition     = azurerm_application_gateway.this.sku[0].tier == "WAF_v2" && azurerm_application_gateway.this.sku[0].name == "WAF_v2"
    error_message = "The gateway should default to the WAF_v2 SKU."
  }

  assert {
    condition     = length(azurerm_web_application_firewall_policy.this) == 1
    error_message = "A WAF policy should be created by default on WAF_v2."
  }

  assert {
    condition     = azurerm_web_application_firewall_policy.this[0].policy_settings[0].mode == "Prevention"
    error_message = "The WAF policy should default to Prevention mode."
  }

  assert {
    condition     = [for s in azurerm_web_application_firewall_policy.this[0].managed_rules[0].managed_rule_set : s.type] == ["Microsoft_DefaultRuleSet", "Microsoft_BotManagerRuleSet"]
    error_message = "The WAF policy should default to DRS 2.1 plus Bot Manager."
  }

  assert {
    condition     = azurerm_web_application_firewall_policy.this[0].name == "waf-agw-ldo-uks-tst-01"
    error_message = "The WAF policy name should default to waf-<gateway name>."
  }

  assert {
    condition     = azurerm_application_gateway.this.ssl_policy[0].policy_name == "AppGwSslPolicy20220101"
    error_message = "The TLS policy should default to AppGwSslPolicy20220101."
  }

  assert {
    condition     = tolist(azurerm_application_gateway.this.zones) == tolist(["1", "2", "3"])
    error_message = "The gateway should be zone-redundant by default."
  }

  assert {
    condition     = azurerm_application_gateway.this.autoscale_configuration[0].min_capacity == 0 && azurerm_application_gateway.this.autoscale_configuration[0].max_capacity == 2
    error_message = "Autoscale should default to 0-2 capacity units."
  }

  assert {
    condition     = azurerm_application_gateway.this.http2_enabled == true
    error_message = "HTTP/2 should be enabled by default."
  }

  assert {
    condition     = azurerm_application_gateway.this.frontend_ip_configuration[0].name == "public-frontend"
    error_message = "The public frontend should carry the module's fixed frontend name."
  }
}

# Priorities: explicit ones win, unset ones are auto-assigned 10, 20... in key order.
run "priorities_auto_assigned" {
  command = plan

  expect_failures = [check.listeners_prefer_tls]

  assert {
    condition     = [for r in azurerm_application_gateway.this.request_routing_rule : r.priority if r.name == "redirect"][0] == 10
    error_message = "The unset priority should be auto-assigned 10."
  }

  assert {
    condition     = [for r in azurerm_application_gateway.this.request_routing_rule : r.priority if r.name == "web"][0] == 500
    error_message = "The explicit priority should be untouched."
  }
}

# Standard_v2 skips the WAF policy entirely.
run "standard_v2_has_no_policy" {
  command = plan

  expect_failures = [check.listeners_prefer_tls]

  variables {
    sku = { tier = "Standard_v2" }
  }

  assert {
    condition     = length(azurerm_web_application_firewall_policy.this) == 0
    error_message = "Standard_v2 should not create a WAF policy."
  }
}

# A fixed capacity turns autoscale off.
run "fixed_capacity_disables_autoscale" {
  command = plan

  expect_failures = [check.listeners_prefer_tls]

  variables {
    sku = { tier = "WAF_v2", capacity = 2 }
  }

  assert {
    condition     = length(azurerm_application_gateway.this.autoscale_configuration) == 0
    error_message = "A pinned capacity should drop the autoscale block."
  }
}

# The resource group is parsed from the id and exposed as an output.
run "parses_resource_group" {
  command = plan

  expect_failures = [check.listeners_prefer_tls]

  assert {
    condition     = output.resource_group_name == "rg-ldo-uks-tst-01"
    error_message = "resource_group_name should be parsed from resource_group_id."
  }
}

# Validation: the retired v1 tiers are rejected.
run "rejects_v1_sku" {
  command = plan

  variables {
    sku = { tier = "WAF" }
  }

  expect_failures = [var.sku, check.listeners_prefer_tls]
}

# Validation: an Https listener needs a certificate.
run "rejects_https_listener_without_certificate" {
  command = plan

  variables {
    listeners = {
      "web-https" = { port = 443, protocol = "Https" }
    }
    request_routing_rules   = {}
    redirect_configurations = {}
  }

  expect_failures = [var.listeners]
}

# Validation: a private listener needs the private frontend.
run "rejects_private_listener_without_private_frontend" {
  command = plan

  variables {
    listeners = {
      "api-http" = { port = 8081, protocol = "Http", frontend = "private" }
    }
    request_routing_rules   = {}
    redirect_configurations = {}
  }

  # The var.listeners validation aborts the plan before checks evaluate, so only it is expected.
  expect_failures = [var.listeners]
}

# Validation: a Basic rule cannot target a backend and a redirect at once.
run "rejects_rule_with_backend_and_redirect" {
  command = plan

  variables {
    request_routing_rules = {
      "web" = {
        listener_key              = "web-http"
        backend_pool_key          = "app"
        backend_http_settings_key = "app-https"
        redirect_key              = "to-https"
      }
    }
  }

  expect_failures = [var.request_routing_rules, check.listeners_prefer_tls]
}

# Validation: bring-your-own policy and a module-created one are mutually exclusive.
run "rejects_byo_policy_with_create" {
  command = plan

  variables {
    firewall_policy_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ldo-uks-tst-01/providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/waf-ldo-uks-tst-01"
  }

  expect_failures = [var.firewall_policy_id, check.listeners_prefer_tls]
}

# Validation: WAF custom rule names are alphanumeric only (Azure rejects hyphens).
run "rejects_hyphenated_custom_rule_name" {
  command = plan

  variables {
    waf_policy = {
      custom_rules = {
        "block-non-uk" = {
          priority = 10
          action   = "Block"
          match_conditions = [{
            match_variables = [{ variable_name = "RemoteAddr" }]
            operator        = "GeoMatch"
            match_values    = ["GB"]
          }]
        }
      }
    }
  }

  expect_failures = [var.waf_policy, check.listeners_prefer_tls]
}
