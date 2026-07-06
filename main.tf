# One Application Gateway (v2) per module call, WAF-flavoured by default: sku WAF_v2 with a
# module-created azurerm_web_application_firewall_policy (Prevention mode, Microsoft Default Rule
# Set 2.1 plus Bot Manager 1.1) associated, zone-redundant, autoscaling, HTTP/2 on, and a TLS 1.2
# floor via the predefined AppGwSslPolicy20220101 policy. Listeners, pools, settings, probes,
# rules, redirects, rewrites, and path maps are maps cross-referenced by key; frontend port blocks
# are derived from the listeners, and routing rule priorities are auto-assigned in key order when
# not set. The resource group is passed by id and parsed.
locals {
  rg                  = provider::azurerm::parse_resource_id(var.resource_group_id)
  resource_group_name = local.rg.resource_group_name

  # Fixed component names inside the gateway; only externally referenced things need caller names.
  gateway_ip_configuration_name = "gateway-ip-config"
  frontend_names                = { public = "public-frontend", private = "private-frontend" }

  # Distinct listener ports become frontend_port blocks named "port-<n>".
  frontend_ports = distinct([for l in values(var.listeners) : l.port])

  # WAF policy: created here on WAF_v2 unless the caller brings their own.
  create_waf_policy  = var.sku.tier == "WAF_v2" && var.waf_policy.create && var.firewall_policy_id == null
  waf_policy_name    = coalesce(var.waf_policy.name, "waf-${var.name}")
  firewall_policy_id = local.create_waf_policy ? azurerm_web_application_firewall_policy.this[0].id : var.firewall_policy_id

  # Unset routing rule priorities are auto-assigned 10, 20, 30... in key order, skipping nothing:
  # explicit priorities are left alone (uniqueness of the explicit ones is validated).
  rule_keys_auto = [for k in sort(keys(var.request_routing_rules)) : k if var.request_routing_rules[k].priority == null]
  rule_priorities = merge(
    { for k, r in var.request_routing_rules : k => r.priority if r.priority != null },
    { for i, k in local.rule_keys_auto : k => (i + 1) * 10 },
  )
}

resource "azurerm_web_application_firewall_policy" "this" {
  count = local.create_waf_policy ? 1 : 0

  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = var.tags

  name = local.waf_policy_name

  policy_settings {
    enabled                                   = var.waf_policy.policy_settings.enabled
    mode                                      = var.waf_policy.mode
    request_body_check                        = var.waf_policy.policy_settings.request_body_check
    request_body_enforcement                  = var.waf_policy.policy_settings.request_body_enforcement
    request_body_inspect_limit_in_kb          = var.waf_policy.policy_settings.request_body_inspect_limit_in_kb
    max_request_body_size_in_kb               = var.waf_policy.policy_settings.max_request_body_size_in_kb
    file_upload_enforcement                   = var.waf_policy.policy_settings.file_upload_enforcement
    file_upload_limit_in_mb                   = var.waf_policy.policy_settings.file_upload_limit_in_mb
    js_challenge_cookie_expiration_in_minutes = var.waf_policy.policy_settings.js_challenge_cookie_expiration_in_minutes

    dynamic "log_scrubbing" {
      for_each = var.waf_policy.policy_settings.log_scrubbing != null ? [var.waf_policy.policy_settings.log_scrubbing] : []

      content {
        enabled = log_scrubbing.value.enabled

        dynamic "rule" {
          for_each = log_scrubbing.value.rules

          content {
            match_variable          = rule.value.match_variable
            selector                = rule.value.selector
            selector_match_operator = rule.value.selector_match_operator
            enabled                 = rule.value.enabled
          }
        }
      }
    }
  }

  managed_rules {
    dynamic "managed_rule_set" {
      for_each = var.waf_policy.managed_rule_sets

      content {
        type    = managed_rule_set.value.type
        version = managed_rule_set.value.version

        dynamic "rule_group_override" {
          for_each = managed_rule_set.value.rule_group_overrides

          content {
            rule_group_name = rule_group_override.value.rule_group_name

            dynamic "rule" {
              for_each = rule_group_override.value.rules

              content {
                id      = rule.value.id
                enabled = rule.value.enabled
                action  = rule.value.action
              }
            }
          }
        }
      }
    }

    dynamic "exclusion" {
      for_each = var.waf_policy.exclusions

      content {
        match_variable          = exclusion.value.match_variable
        selector                = exclusion.value.selector
        selector_match_operator = exclusion.value.selector_match_operator

        dynamic "excluded_rule_set" {
          for_each = exclusion.value.excluded_rule_sets

          content {
            type    = excluded_rule_set.value.type
            version = excluded_rule_set.value.version

            dynamic "rule_group" {
              for_each = excluded_rule_set.value.rule_groups

              content {
                rule_group_name = rule_group.value.rule_group_name
                excluded_rules  = rule_group.value.excluded_rules
              }
            }
          }
        }
      }
    }
  }

  dynamic "custom_rules" {
    for_each = var.waf_policy.custom_rules

    content {
      name                 = custom_rules.key
      priority             = custom_rules.value.priority
      rule_type            = custom_rules.value.rule_type
      action               = custom_rules.value.action
      enabled              = custom_rules.value.enabled
      rate_limit_duration  = custom_rules.value.rate_limit_duration
      rate_limit_threshold = custom_rules.value.rate_limit_threshold
      group_rate_limit_by  = custom_rules.value.group_rate_limit_by

      dynamic "match_conditions" {
        for_each = custom_rules.value.match_conditions

        content {
          operator           = match_conditions.value.operator
          match_values       = match_conditions.value.match_values
          negation_condition = match_conditions.value.negation_condition
          transforms         = match_conditions.value.transforms

          dynamic "match_variables" {
            for_each = match_conditions.value.match_variables

            content {
              variable_name = match_variables.value.variable_name
              selector      = match_variables.value.selector
            }
          }
        }
      }
    }
  }
}

resource "azurerm_application_gateway" "this" {
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = var.tags

  name                              = var.name
  zones                             = var.zones
  http2_enabled                     = var.http2_enabled
  fips_enabled                      = var.fips_enabled
  firewall_policy_id                = local.firewall_policy_id
  force_firewall_policy_association = local.firewall_policy_id != null ? var.force_firewall_policy_association : null

  sku {
    tier     = var.sku.tier
    name     = coalesce(var.sku.name, var.sku.tier)
    capacity = var.sku.capacity
  }

  # A fixed capacity turns autoscale off.
  dynamic "autoscale_configuration" {
    for_each = var.sku.capacity == null ? [var.autoscale_configuration] : []

    content {
      min_capacity = autoscale_configuration.value.min_capacity
      max_capacity = autoscale_configuration.value.max_capacity
    }
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = var.gateway_subnet_id
  }

  frontend_ip_configuration {
    name                 = local.frontend_names.public
    public_ip_address_id = var.public_ip_address_id
  }

  # The optional private frontend lives on the gateway subnet with a static address.
  dynamic "frontend_ip_configuration" {
    for_each = var.private_frontend != null ? [var.private_frontend] : []

    content {
      name                          = local.frontend_names.private
      subnet_id                     = var.gateway_subnet_id
      private_ip_address            = frontend_ip_configuration.value.private_ip_address
      private_ip_address_allocation = "Static"
    }
  }

  dynamic "frontend_port" {
    for_each = toset(local.frontend_ports)

    content {
      name = "port-${frontend_port.value}"
      port = frontend_port.value
    }
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []

    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  ssl_policy {
    policy_type          = var.ssl_policy.policy_type
    policy_name          = var.ssl_policy.policy_type == "Predefined" ? var.ssl_policy.policy_name : null
    min_protocol_version = var.ssl_policy.min_protocol_version
    cipher_suites        = var.ssl_policy.cipher_suites
    disabled_protocols   = var.ssl_policy.disabled_protocols
  }

  dynamic "global" {
    for_each = var.global_buffering != null ? [var.global_buffering] : []

    content {
      request_buffering_enabled  = global.value.request_buffering_enabled
      response_buffering_enabled = global.value.response_buffering_enabled
    }
  }

  dynamic "backend_address_pool" {
    for_each = var.backend_pools

    content {
      name         = backend_address_pool.key
      fqdns        = backend_address_pool.value.fqdns
      ip_addresses = backend_address_pool.value.ip_addresses
    }
  }

  dynamic "probe" {
    for_each = var.probes

    content {
      name     = probe.key
      protocol = probe.value.protocol
      path     = probe.value.path
      # Without an explicit host, pick it from the backend http settings (unless the caller chose).
      host                                      = probe.value.host
      pick_host_name_from_backend_http_settings = coalesce(probe.value.pick_host_name_from_backend_http_settings, probe.value.host == null)
      port                                      = probe.value.port
      interval                                  = probe.value.interval
      timeout                                   = probe.value.timeout
      unhealthy_threshold                       = probe.value.unhealthy_threshold
      minimum_servers                           = probe.value.minimum_servers
      proxy_protocol_header_enabled             = probe.value.proxy_protocol_header_enabled

      dynamic "match" {
        for_each = probe.value.match != null ? [probe.value.match] : []

        content {
          status_code = match.value.status_code
          body        = match.value.body
        }
      }
    }
  }

  dynamic "backend_http_settings" {
    for_each = var.backend_http_settings

    content {
      name                                 = backend_http_settings.key
      port                                 = backend_http_settings.value.port
      protocol                             = backend_http_settings.value.protocol
      cookie_based_affinity                = backend_http_settings.value.cookie_based_affinity
      affinity_cookie_name                 = backend_http_settings.value.affinity_cookie_name
      request_timeout                      = backend_http_settings.value.request_timeout
      path                                 = backend_http_settings.value.path
      host_name                            = backend_http_settings.value.host_name
      pick_host_name_from_backend_address  = backend_http_settings.value.pick_host_name_from_backend_address
      probe_name                           = backend_http_settings.value.probe_key
      trusted_root_certificate_names       = backend_http_settings.value.trusted_root_certificate_names
      certificate_chain_validation_enabled = backend_http_settings.value.certificate_chain_validation_enabled
      dedicated_backend_connection_enabled = backend_http_settings.value.dedicated_backend_connection_enabled
      sni_name                             = backend_http_settings.value.sni_name
      sni_validation_enabled               = backend_http_settings.value.sni_validation_enabled

      dynamic "authentication_certificate" {
        for_each = backend_http_settings.value.authentication_certificate_names

        content {
          name = authentication_certificate.value
        }
      }

      dynamic "connection_draining" {
        for_each = backend_http_settings.value.connection_draining != null ? [backend_http_settings.value.connection_draining] : []

        content {
          enabled           = connection_draining.value.enabled
          drain_timeout_sec = connection_draining.value.drain_timeout_sec
        }
      }
    }
  }

  dynamic "http_listener" {
    for_each = var.listeners

    content {
      name                           = http_listener.key
      frontend_ip_configuration_name = local.frontend_names[http_listener.value.frontend]
      frontend_port_name             = "port-${http_listener.value.port}"
      protocol                       = http_listener.value.protocol
      host_name                      = http_listener.value.host_name
      host_names                     = http_listener.value.host_names
      require_sni                    = http_listener.value.require_sni
      ssl_certificate_name           = try(coalesce(http_listener.value.ssl_certificate_key, http_listener.value.ssl_certificate_name), null)
      ssl_profile_name               = http_listener.value.ssl_profile_key
      firewall_policy_id             = http_listener.value.firewall_policy_id

      dynamic "custom_error_configuration" {
        for_each = http_listener.value.custom_error_configurations

        content {
          status_code           = custom_error_configuration.value.status_code
          custom_error_page_url = custom_error_configuration.value.custom_error_page_url
        }
      }
    }
  }

  dynamic "request_routing_rule" {
    for_each = var.request_routing_rules

    content {
      name                        = request_routing_rule.key
      rule_type                   = request_routing_rule.value.rule_type
      priority                    = local.rule_priorities[request_routing_rule.key]
      http_listener_name          = request_routing_rule.value.listener_key
      backend_address_pool_name   = request_routing_rule.value.backend_pool_key
      backend_http_settings_name  = request_routing_rule.value.backend_http_settings_key
      redirect_configuration_name = request_routing_rule.value.redirect_key
      rewrite_rule_set_name       = request_routing_rule.value.rewrite_rule_set_key
      url_path_map_name           = request_routing_rule.value.url_path_map_key
    }
  }

  dynamic "redirect_configuration" {
    for_each = var.redirect_configurations

    content {
      name                 = redirect_configuration.key
      redirect_type        = redirect_configuration.value.redirect_type
      target_listener_name = redirect_configuration.value.target_listener_key
      target_url           = redirect_configuration.value.target_url
      include_path         = redirect_configuration.value.include_path
      include_query_string = redirect_configuration.value.include_query_string
    }
  }

  dynamic "rewrite_rule_set" {
    for_each = var.rewrite_rule_sets

    content {
      name = rewrite_rule_set.key

      dynamic "rewrite_rule" {
        for_each = rewrite_rule_set.value.rules

        content {
          name          = rewrite_rule.value.name
          rule_sequence = rewrite_rule.value.rule_sequence

          dynamic "condition" {
            for_each = rewrite_rule.value.conditions

            content {
              variable    = condition.value.variable
              pattern     = condition.value.pattern
              ignore_case = condition.value.ignore_case
              negate      = condition.value.negate
            }
          }

          dynamic "request_header_configuration" {
            for_each = rewrite_rule.value.request_header_configurations

            content {
              header_name  = request_header_configuration.value.header_name
              header_value = request_header_configuration.value.header_value
            }
          }

          dynamic "response_header_configuration" {
            for_each = rewrite_rule.value.response_header_configurations

            content {
              header_name  = response_header_configuration.value.header_name
              header_value = response_header_configuration.value.header_value
            }
          }

          dynamic "url" {
            for_each = rewrite_rule.value.url != null ? [rewrite_rule.value.url] : []

            content {
              path         = url.value.path
              query_string = url.value.query_string
              components   = url.value.components
              reroute      = url.value.reroute
            }
          }
        }
      }
    }
  }

  dynamic "url_path_map" {
    for_each = var.url_path_maps

    content {
      name                                = url_path_map.key
      default_backend_address_pool_name   = url_path_map.value.default_backend_pool_key
      default_backend_http_settings_name  = url_path_map.value.default_backend_http_settings_key
      default_redirect_configuration_name = url_path_map.value.default_redirect_key
      default_rewrite_rule_set_name       = url_path_map.value.default_rewrite_rule_set_key

      dynamic "path_rule" {
        for_each = url_path_map.value.path_rules

        content {
          name                        = path_rule.key
          paths                       = path_rule.value.paths
          backend_address_pool_name   = path_rule.value.backend_pool_key
          backend_http_settings_name  = path_rule.value.backend_http_settings_key
          redirect_configuration_name = path_rule.value.redirect_key
          rewrite_rule_set_name       = path_rule.value.rewrite_rule_set_key
          firewall_policy_id          = path_rule.value.firewall_policy_id
        }
      }
    }
  }

  # The certificates map is sensitive, which cannot drive for_each directly; the key set is not a
  # secret, so iterate that (the data and password values stay sensitive).
  dynamic "ssl_certificate" {
    for_each = nonsensitive(toset(keys(var.ssl_certificates)))

    content {
      name                = ssl_certificate.value
      data                = var.ssl_certificates[ssl_certificate.value].data
      password            = var.ssl_certificates[ssl_certificate.value].password
      key_vault_secret_id = var.ssl_certificates[ssl_certificate.value].key_vault_secret_id
    }
  }

  dynamic "trusted_root_certificate" {
    for_each = var.trusted_root_certificates

    content {
      name                = trusted_root_certificate.key
      data                = trusted_root_certificate.value.data
      key_vault_secret_id = trusted_root_certificate.value.key_vault_secret_id
    }
  }

  dynamic "trusted_client_certificate" {
    for_each = var.trusted_client_certificates

    content {
      name = trusted_client_certificate.key
      data = trusted_client_certificate.value.data
    }
  }

  dynamic "ssl_profile" {
    for_each = var.ssl_profiles

    content {
      name                                 = ssl_profile.key
      trusted_client_certificate_names     = ssl_profile.value.trusted_client_certificate_keys
      verify_client_certificate_revocation = ssl_profile.value.verify_client_certificate_revocation

      dynamic "ssl_policy" {
        for_each = ssl_profile.value.ssl_policy != null ? [ssl_profile.value.ssl_policy] : []

        content {
          policy_type          = ssl_policy.value.policy_type
          policy_name          = ssl_policy.value.policy_name
          min_protocol_version = ssl_policy.value.min_protocol_version
          cipher_suites        = ssl_policy.value.cipher_suites
          disabled_protocols   = ssl_policy.value.disabled_protocols
        }
      }
    }
  }

  dynamic "authentication_certificate" {
    for_each = var.authentication_certificates

    content {
      name = authentication_certificate.key
      data = authentication_certificate.value.data
    }
  }

  dynamic "private_link_configuration" {
    for_each = var.private_link_configurations

    content {
      name = private_link_configuration.key

      dynamic "ip_configuration" {
        for_each = private_link_configuration.value.ip_configurations

        content {
          name                          = ip_configuration.key
          subnet_id                     = ip_configuration.value.subnet_id
          primary                       = ip_configuration.value.primary
          private_ip_address_allocation = ip_configuration.value.private_ip_address_allocation
          private_ip_address            = ip_configuration.value.private_ip_address
        }
      }
    }
  }

  dynamic "custom_error_configuration" {
    for_each = var.custom_error_configurations

    content {
      status_code           = custom_error_configuration.value.status_code
      custom_error_page_url = custom_error_configuration.value.custom_error_page_url
    }
  }
}
