variable "authentication_certificates" {
  description = "v1-style backend authentication certificates keyed by name (kept for completeness; prefer trusted_root_certificates on v2)."
  type = map(object({
    data = string
  }))
  default = {}
}

variable "autoscale_configuration" {
  description = "Autoscale bounds, on by default (0 to 2 capacity units). Ignored when sku.capacity pins a fixed count."
  type = object({
    min_capacity = optional(number, 0)
    max_capacity = optional(number, 2)
  })
  default = {}
}

variable "backend_http_settings" {
  description = "Backend HTTP settings keyed by name. Defaults speak HTTPS to the backend (port 443, protocol Https) with cookie affinity off; probe_key wires a probe from probes."
  type = map(object({
    port                                 = optional(number, 443)
    protocol                             = optional(string, "Https")
    cookie_based_affinity                = optional(string, "Disabled")
    affinity_cookie_name                 = optional(string)
    request_timeout                      = optional(number, 30)
    path                                 = optional(string)
    host_name                            = optional(string)
    pick_host_name_from_backend_address  = optional(bool)
    probe_key                            = optional(string)
    trusted_root_certificate_names       = optional(list(string))
    certificate_chain_validation_enabled = optional(bool)
    dedicated_backend_connection_enabled = optional(bool)
    sni_name                             = optional(string)
    sni_validation_enabled               = optional(bool)
    authentication_certificate_names     = optional(list(string), [])
    connection_draining = optional(object({
      enabled           = optional(bool, true)
      drain_timeout_sec = optional(number, 60)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.backend_http_settings) : contains(["Http", "Https"], s.protocol)])
    error_message = "backend_http_settings protocol must be Http or Https."
  }

  validation {
    condition     = alltrue([for s in values(var.backend_http_settings) : s.probe_key == null || contains(keys(var.probes), coalesce(s.probe_key, "-"))])
    error_message = "every backend_http_settings probe_key must match a key in probes."
  }

  validation {
    condition = alltrue([
      for s in values(var.backend_http_settings) :
      s.probe_key == null || !try(coalesce(var.probes[s.probe_key].pick_host_name_from_backend_http_settings, false), false) || s.host_name != null || coalesce(s.pick_host_name_from_backend_address, false)
    ])
    error_message = "a probe with pick_host_name_from_backend_http_settings needs its backend http settings to pin a host_name or set pick_host_name_from_backend_address (Azure rejects it with ApplicationGatewayBackendHttpSettingsIncompatibleProbeSettingPickHostName)."
  }
}

variable "backend_pools" {
  description = "Backend address pools keyed by pool name: FQDNs, ip addresses, or empty for NIC-attached backends."
  type = map(object({
    fqdns        = optional(list(string))
    ip_addresses = optional(list(string))
  }))
  default = {}
}

variable "custom_error_configurations" {
  description = "Gateway-wide custom error pages: status code to a publicly reachable html url."
  type = list(object({
    status_code           = string
    custom_error_page_url = string
  }))
  default = []
}

variable "fips_enabled" {
  description = "Whether FIPS 140-2 mode is enabled."
  type        = bool
  default     = false
}

variable "firewall_policy_id" {
  description = "Bring-your-own WAF policy id. Mutually exclusive with the module-created policy (waf_policy.create)."
  type        = string
  default     = null

  validation {
    condition     = var.firewall_policy_id == null || var.waf_policy.create == false
    error_message = "firewall_policy_id and a module-created WAF policy are mutually exclusive: set waf_policy.create = false to bring your own."
  }
}

variable "force_firewall_policy_association" {
  description = "Whether the WAF policy association is forced during association changes."
  type        = bool
  default     = true
}

variable "gateway_subnet_id" {
  description = "Subnet the gateway lives in (a dedicated subnet; nothing else may share it)."
  type        = string
}

variable "global_buffering" {
  description = "Gateway-wide request and response buffering toggles."
  type = object({
    request_buffering_enabled  = optional(bool, true)
    response_buffering_enabled = optional(bool, true)
  })
  default = null
}

variable "http2_enabled" {
  description = "Whether HTTP/2 is enabled on the frontends."
  type        = bool
  default     = true
}

variable "identity" {
  description = "Managed identity for the gateway (a user-assigned identity is required to read Key Vault certificates via key_vault_secret_id)."
  type = object({
    type         = optional(string, "UserAssigned")
    identity_ids = optional(list(string))
  })
  default = null
}

variable "listeners" {
  description = <<-EOT
    HTTP(S) listeners keyed by listener name. frontend picks "public" (default) or "private" (needs
    private_frontend). The frontend port block is derived from port automatically. protocol is an
    explicit choice, no default: Https requires ssl_certificate_key (or ssl_certificate_name for a
    certificate managed elsewhere), and Http is flagged by a check as a TLS nudge.
  EOT
  type = map(object({
    port                 = number
    protocol             = string
    frontend             = optional(string, "public")
    host_name            = optional(string)
    host_names           = optional(list(string))
    require_sni          = optional(bool)
    ssl_certificate_key  = optional(string)
    ssl_certificate_name = optional(string)
    ssl_profile_key      = optional(string)
    firewall_policy_id   = optional(string)
    custom_error_configurations = optional(list(object({
      status_code           = string
      custom_error_page_url = string
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for l in values(var.listeners) : contains(["Http", "Https"], l.protocol)])
    error_message = "listener protocol must be Http or Https."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : contains(["public", "private"], l.frontend)])
    error_message = "listener frontend must be public or private."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.frontend != "private"]) || var.private_frontend != null
    error_message = "a listener on the private frontend needs private_frontend to be set."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.protocol != "Https" || l.ssl_certificate_key != null || l.ssl_certificate_name != null])
    error_message = "Https listeners need a certificate: set ssl_certificate_key (from ssl_certificates) or ssl_certificate_name."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.ssl_certificate_key == null || contains(keys(var.ssl_certificates), coalesce(l.ssl_certificate_key, "-"))])
    error_message = "every listener ssl_certificate_key must match a key in ssl_certificates."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.ssl_profile_key == null || contains(keys(var.ssl_profiles), coalesce(l.ssl_profile_key, "-"))])
    error_message = "every listener ssl_profile_key must match a key in ssl_profiles."
  }
}

variable "location" {
  description = "Azure region for the gateway."
  type        = string
}

variable "name" {
  description = "Name of the application gateway (agw-ldo-uks-prd-001)."
  type        = string
}

variable "private_frontend" {
  description = "Optional \"private\" frontend on the gateway subnet. private_ip_address pins a static address (required by Azure for a v2 private frontend)."
  type = object({
    private_ip_address = string
  })
  default = null
}

variable "private_link_configurations" {
  description = "Private link configurations keyed by name, enabling Private Endpoint connectivity to the gateway frontends."
  type = map(object({
    ip_configurations = map(object({
      subnet_id                     = string
      primary                       = bool
      private_ip_address_allocation = optional(string, "Dynamic")
      private_ip_address            = optional(string)
    }))
  }))
  default = {}
}

variable "probes" {
  description = "Health probes keyed by probe name. protocol defaults to Http; host defaults to localhost (Azure's default-probe convention). pick_host_name_from_backend_http_settings is only legal when every backend http settings referencing the probe pins a host_name or picks from the backend address, and that is validated."
  type = map(object({
    protocol                                  = optional(string, "Http")
    path                                      = optional(string, "/")
    host                                      = optional(string)
    pick_host_name_from_backend_http_settings = optional(bool)
    port                                      = optional(number)
    interval                                  = optional(number, 30)
    timeout                                   = optional(number, 30)
    unhealthy_threshold                       = optional(number, 3)
    minimum_servers                           = optional(number)
    proxy_protocol_header_enabled             = optional(bool)
    match = optional(object({
      status_code = list(string)
      body        = optional(string)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for p in values(var.probes) : contains(["Http", "Https", "Tcp", "Tls"], p.protocol)])
    error_message = "probe protocol must be Http, Https, Tcp, or Tls."
  }

  validation {
    condition     = alltrue([for p in values(var.probes) : !contains(["Http", "Https"], p.protocol) || startswith(p.path, "/")])
    error_message = "Http and Https probe paths must start with /."
  }
}

variable "public_ip_address_id" {
  description = "Standard public ip the \"public\" frontend fronts (compose the public-ip module). v2 gateways require a public frontend."
  type        = string
}

variable "redirect_configurations" {
  description = "Redirect configurations keyed by name: target_listener_key redirects to another listener, target_url to an external url."
  type = map(object({
    redirect_type        = optional(string, "Permanent")
    target_listener_key  = optional(string)
    target_url           = optional(string)
    include_path         = optional(bool, true)
    include_query_string = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.redirect_configurations) :
      (r.target_listener_key != null && r.target_url == null) || (r.target_listener_key == null && r.target_url != null)
    ])
    error_message = "every redirect sets exactly one of target_listener_key or target_url."
  }
}

variable "request_routing_rules" {
  description = <<-EOT
    Routing rules keyed by rule name. listener_key picks the listener; a Basic rule targets a
    backend (backend_pool_key + backend_http_settings_key) or a redirect (redirect_key); a
    PathBasedRouting rule targets a url_path_map_key. priority is optional: unset rules are
    auto-assigned 10, 20, 30... in key order (explicit priorities are left alone).
  EOT
  type = map(object({
    listener_key              = string
    rule_type                 = optional(string, "Basic")
    priority                  = optional(number)
    backend_pool_key          = optional(string)
    backend_http_settings_key = optional(string)
    redirect_key              = optional(string)
    rewrite_rule_set_key      = optional(string)
    url_path_map_key          = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.request_routing_rules) : contains(["Basic", "PathBasedRouting"], r.rule_type)])
    error_message = "rule_type must be Basic or PathBasedRouting."
  }

  validation {
    condition     = alltrue([for r in values(var.request_routing_rules) : contains(keys(var.listeners), r.listener_key)])
    error_message = "every routing rule listener_key must match a key in listeners."
  }

  validation {
    condition = alltrue([
      for r in values(var.request_routing_rules) :
      r.rule_type == "PathBasedRouting" ? r.url_path_map_key != null : (
        (r.backend_pool_key != null && r.backend_http_settings_key != null && r.redirect_key == null) ||
        (r.backend_pool_key == null && r.backend_http_settings_key == null && r.redirect_key != null)
      )
    ])
    error_message = "a Basic rule targets a backend (backend_pool_key + backend_http_settings_key) or a redirect (redirect_key), never both; a PathBasedRouting rule needs url_path_map_key."
  }

  validation {
    condition     = length(distinct([for r in values(var.request_routing_rules) : r.priority if r.priority != null])) == length([for r in values(var.request_routing_rules) : r.priority if r.priority != null])
    error_message = "explicit routing rule priorities must be unique."
  }
}

variable "resource_group_id" {
  description = "Resource id of the resource group the gateway is created in. The resource group name and subscription are parsed from this id."
  type        = string

  validation {
    condition     = try(provider::azurerm::parse_resource_id(var.resource_group_id).resource_type, "") == "resourceGroups"
    error_message = "resource_group_id must be a resource group resource id."
  }
}

variable "rewrite_rule_sets" {
  description = "Rewrite rule sets keyed by set name; each holds an ordered list of rewrite rules (rule_sequence decides order)."
  type = map(object({
    rules = list(object({
      name          = string
      rule_sequence = number
      conditions = optional(list(object({
        variable    = string
        pattern     = string
        ignore_case = optional(bool)
        negate      = optional(bool)
      })), [])
      request_header_configurations = optional(list(object({
        header_name  = string
        header_value = string
      })), [])
      response_header_configurations = optional(list(object({
        header_name  = string
        header_value = string
      })), [])
      url = optional(object({
        path         = optional(string)
        query_string = optional(string)
        components   = optional(string)
        reroute      = optional(bool)
      }))
    }))
  }))
  default = {}
}

variable "sku" {
  description = "Gateway SKU. Only the v2 tiers exist now (v1 Standard/WAF retired April 2026). tier WAF_v2 (default) or Standard_v2; name defaults to the tier. capacity pins a fixed instance count and turns off autoscale."
  type = object({
    tier     = optional(string, "WAF_v2")
    name     = optional(string)
    capacity = optional(number)
  })
  default = {}

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.sku.tier)
    error_message = "sku.tier must be Standard_v2 or WAF_v2: the v1 tiers (Standard, WAF) are retired."
  }
}

variable "ssl_certificates" {
  description = "TLS certificates keyed by certificate name: inline PFX (data + password) or a Key Vault secret id (needs a user-assigned identity)."
  type = map(object({
    data                = optional(string)
    password            = optional(string)
    key_vault_secret_id = optional(string)
  }))
  default   = {}
  sensitive = true
}

variable "ssl_policy" {
  description = "Gateway-wide TLS policy. Defaults to the predefined AppGwSslPolicy20220101 profile (TLS 1.2 floor with modern ciphers). Set policy_type Custom/CustomV2 with min_protocol_version and cipher_suites to hand-roll."
  type = object({
    policy_type          = optional(string, "Predefined")
    policy_name          = optional(string, "AppGwSslPolicy20220101")
    min_protocol_version = optional(string)
    cipher_suites        = optional(list(string))
    disabled_protocols   = optional(list(string))
  })
  default = {}
}

variable "ssl_profiles" {
  description = "SSL profiles keyed by profile name, for per-listener mutual TLS and TLS policy overrides."
  type = map(object({
    trusted_client_certificate_keys      = optional(list(string), [])
    verify_client_certificate_issuer_dn  = optional(bool)
    verify_client_certificate_revocation = optional(string)
    ssl_policy = optional(object({
      policy_type          = optional(string)
      policy_name          = optional(string)
      min_protocol_version = optional(string)
      cipher_suites        = optional(list(string))
      disabled_protocols   = optional(list(string))
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to the gateway and its WAF policy."
  type        = map(string)
  default     = {}
}

variable "trusted_client_certificates" {
  description = "Trusted client CA certificates keyed by name (inline CER data), referenced by ssl profiles for mutual TLS."
  type = map(object({
    data = string
  }))
  default = {}
}

variable "trusted_root_certificates" {
  description = "Trusted root certificates keyed by name (inline CER data or a Key Vault secret id), referenced by backend http settings for backend TLS validation."
  type = map(object({
    data                = optional(string)
    key_vault_secret_id = optional(string)
  }))
  default = {}
}

variable "url_path_maps" {
  description = "URL path maps keyed by map name, for PathBasedRouting rules: a default backend or redirect plus path rules."
  type = map(object({
    default_backend_pool_key          = optional(string)
    default_backend_http_settings_key = optional(string)
    default_redirect_key              = optional(string)
    default_rewrite_rule_set_key      = optional(string)
    path_rules = map(object({
      paths                     = list(string)
      backend_pool_key          = optional(string)
      backend_http_settings_key = optional(string)
      redirect_key              = optional(string)
      rewrite_rule_set_key      = optional(string)
      firewall_policy_id        = optional(string)
    }))
  }))
  default = {}
}

variable "waf_policy" {
  description = <<-EOT
    The WAF policy the module creates and associates when sku.tier is WAF_v2 (ignored on
    Standard_v2). Secure defaults: Prevention mode, Microsoft Default Rule Set 2.1 plus the Bot
    Manager rule set 1.1, request body inspection on. Set create = false to bring your own via
    firewall_policy_id. Fields: name (defaults to waf-<gateway name>), mode, managed_rule_sets,
    exclusions, custom_rules (rate limiting, geo blocks, ip allow/deny), and policy_settings.
  EOT
  type = object({
    create = optional(bool, true)
    name   = optional(string)
    mode   = optional(string, "Prevention")

    managed_rule_sets = optional(list(object({
      type    = optional(string, "Microsoft_DefaultRuleSet")
      version = string
      rule_group_overrides = optional(list(object({
        rule_group_name = string
        rules = optional(list(object({
          id      = string
          enabled = optional(bool)
          action  = optional(string)
        })), [])
      })), [])
      })), [
      { type = "Microsoft_DefaultRuleSet", version = "2.1" },
      { type = "Microsoft_BotManagerRuleSet", version = "1.1" },
    ])

    exclusions = optional(list(object({
      match_variable          = string
      selector                = string
      selector_match_operator = string
      excluded_rule_sets = optional(list(object({
        type    = optional(string)
        version = optional(string)
        rule_groups = optional(list(object({
          rule_group_name = string
          excluded_rules  = optional(list(string))
        })), [])
      })), [])
    })), [])

    custom_rules = optional(map(object({
      priority             = number
      rule_type            = optional(string, "MatchRule")
      action               = string
      enabled              = optional(bool)
      rate_limit_duration  = optional(string)
      rate_limit_threshold = optional(number)
      group_rate_limit_by  = optional(string)
      match_conditions = list(object({
        match_variables = list(object({
          variable_name = string
          selector      = optional(string)
        }))
        operator           = string
        match_values       = optional(list(string))
        negation_condition = optional(bool)
        transforms         = optional(list(string))
      }))
    })), {})

    policy_settings = optional(object({
      enabled                                   = optional(bool, true)
      request_body_check                        = optional(bool, true)
      request_body_enforcement                  = optional(bool)
      request_body_inspect_limit_in_kb          = optional(number)
      max_request_body_size_in_kb               = optional(number, 128)
      file_upload_enforcement                   = optional(bool)
      file_upload_limit_in_mb                   = optional(number, 100)
      js_challenge_cookie_expiration_in_minutes = optional(number)
      log_scrubbing = optional(object({
        enabled = optional(bool, true)
        rules = optional(list(object({
          match_variable          = string
          selector                = optional(string)
          selector_match_operator = optional(string)
          enabled                 = optional(bool)
        })), [])
      }))
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["Prevention", "Detection"], var.waf_policy.mode)
    error_message = "waf_policy.mode must be Prevention or Detection."
  }

  validation {
    condition     = length(distinct([for r in values(var.waf_policy.custom_rules) : r.priority])) == length(values(var.waf_policy.custom_rules))
    error_message = "waf_policy custom rule priorities must be unique."
  }

  validation {
    condition     = alltrue([for name in keys(var.waf_policy.custom_rules) : can(regex("^[a-zA-Z][a-zA-Z0-9]{0,127}$", name))])
    error_message = "WAF custom rule names must be alphanumeric starting with a letter, no hyphens (Azure rejects them with ApplicationGatewayFirewallCustomRuleInvalidName)."
  }
}

variable "zones" {
  description = "Availability zones the gateway spans. Zone-redundant by default; set [] for regions without zones."
  type        = set(string)
  default     = ["1", "2", "3"]
}
