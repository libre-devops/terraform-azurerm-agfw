locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  vnet_name = "vnet-${var.short}-${var.loc}-${terraform.workspace}-002"
  pip_name  = "pip-${var.short}-${var.loc}-${terraform.workspace}-002"
  agw_name  = "agw-${var.short}-${var.loc}-${terraform.workspace}-002"
  waf_name  = "waf-${var.short}-${var.loc}-${terraform.workspace}-002"
  snet_agw  = "snet-agw-${local.vnet_name}"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
  additional_tags = { Application = "terraform-azurerm-agfw" }
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "network" {
  source  = "libre-devops/network/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  vnet_name     = local.vnet_name
  address_space = ["10.0.0.0/16"]
  subnets       = { (local.snet_agw) = { address_prefixes = ["10.0.1.0/24"] } }
}

module "public_ip" {
  source  = "libre-devops/public-ip/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  public_ips = {
    (local.pip_name) = { zones = ["1", "2", "3"] }
  }
}

# Complete call: every certificate-free feature of the module on one WAF_v2 gateway. (TLS
# listeners, ssl profiles, and Key Vault certificates need certificate material, so they are
# exercised in the mocked tests instead of live.)
#
# - A private frontend (static ip on the gateway subnet) alongside the public one.
# - Explicit autoscale bounds and global buffering toggles.
# - Two pools (ip-based and fqdn-based), Http settings with connection draining, a custom probe
#   with a match block.
# - Three listeners and rule styles: a basic rule with a rewrite set (security response headers),
#   a redirect rule to an external url, and a path-based rule with a url path map.
# - A tuned WAF policy: Prevention mode with the Microsoft Default Rule Set 2.1 and Bot Manager
#   1.1, a rule override, an exclusion, a per-client rate limit, a geo-block custom rule, and log
#   scrubbing for a bearer token query parameter.
module "agfw" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  name                 = local.agw_name
  gateway_subnet_id    = module.network.subnet_ids[local.snet_agw]
  public_ip_address_id = module.public_ip.public_ip_ids[local.pip_name]

  private_frontend = { private_ip_address = "10.0.1.10" }

  autoscale_configuration = { min_capacity = 1, max_capacity = 3 }
  global_buffering        = { request_buffering_enabled = true, response_buffering_enabled = false }

  waf_policy = {
    name = local.waf_name
    mode = "Prevention"

    managed_rule_sets = [
      {
        type    = "Microsoft_DefaultRuleSet"
        version = "2.1"
        rule_group_overrides = [{
          rule_group_name = "PHP"
          rules           = [{ id = "933100", enabled = false }]
        }]
      },
      { type = "Microsoft_BotManagerRuleSet", version = "1.1" },
    ]

    exclusions = [{
      match_variable          = "RequestCookieNames"
      selector                = "session-affinity"
      selector_match_operator = "Equals"
    }]

    custom_rules = {
      "rate-limit-per-ip" = {
        priority             = 10
        rule_type            = "RateLimitRule"
        action               = "Block"
        rate_limit_duration  = "OneMin"
        rate_limit_threshold = 300
        group_rate_limit_by  = "ClientAddr"
        match_conditions = [{
          match_variables = [{ variable_name = "RemoteAddr" }]
          operator        = "IPMatch"
          match_values    = ["0.0.0.0/0"]
        }]
      }
      "block-non-uk" = {
        priority  = 20
        rule_type = "MatchRule"
        action    = "Block"
        match_conditions = [{
          match_variables    = [{ variable_name = "RemoteAddr" }]
          operator           = "GeoMatch"
          match_values       = ["GB"]
          negation_condition = true
        }]
      }
    }

    policy_settings = {
      max_request_body_size_in_kb = 256
      file_upload_limit_in_mb     = 50
      log_scrubbing = {
        rules = [{
          match_variable          = "RequestArgNames"
          selector                = "token"
          selector_match_operator = "Equals"
        }]
      }
    }
  }

  backend_pools = {
    "app" = { ip_addresses = ["10.0.2.10", "10.0.2.11"] }
    "api" = { fqdns = ["api.internal.libredevops.org"] }
  }

  probes = {
    "app-health" = {
      path                = "/healthz"
      interval            = 15
      timeout             = 15
      unhealthy_threshold = 2
      match               = { status_code = ["200-399"] }
    }
  }

  backend_http_settings = {
    "app-http" = {
      port                = 8080
      protocol            = "Http"
      probe_key           = "app-health"
      connection_draining = { drain_timeout_sec = 30 }
    }
    "api-http" = {
      port                                = 8081
      protocol                            = "Http"
      pick_host_name_from_backend_address = true
    }
  }

  listeners = {
    "web-http"      = { port = 80, protocol = "Http" }
    "redirect-http" = { port = 8080, protocol = "Http" }
    "api-http"      = { port = 8081, protocol = "Http", frontend = "private" }
  }

  request_routing_rules = {
    "web" = {
      listener_key              = "web-http"
      backend_pool_key          = "app"
      backend_http_settings_key = "app-http"
      rewrite_rule_set_key      = "security-headers"
      priority                  = 100
    }
    "docs-redirect" = {
      listener_key = "redirect-http"
      redirect_key = "to-docs"
    }
    "api-paths" = {
      listener_key     = "api-http"
      rule_type        = "PathBasedRouting"
      url_path_map_key = "api-map"
    }
  }

  redirect_configurations = {
    "to-docs" = {
      target_url   = "https://libredevops.org"
      include_path = false
    }
  }

  rewrite_rule_sets = {
    "security-headers" = {
      rules = [{
        name          = "add-security-headers"
        rule_sequence = 100
        response_header_configurations = [
          { header_name = "X-Content-Type-Options", header_value = "nosniff" },
          { header_name = "Strict-Transport-Security", header_value = "max-age=31536000; includeSubDomains" },
        ]
      }]
    }
  }

  url_path_maps = {
    "api-map" = {
      default_backend_pool_key          = "app"
      default_backend_http_settings_key = "app-http"
      path_rules = {
        "api" = {
          paths                     = ["/api/*"]
          backend_pool_key          = "api"
          backend_http_settings_key = "api-http"
        }
      }
    }
  }
}
