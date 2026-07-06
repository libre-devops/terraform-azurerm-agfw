<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform Azure Application Gateway Firewall

Azure Application Gateway v2 with its Web Application Firewall policy in one module: WAF_v2 with a
Prevention-mode policy on the Microsoft Default Rule Set by default.

[![CI](https://github.com/libre-devops/terraform-azurerm-agfw/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azurerm-agfw/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azurerm-agfw?sort=semver&label=release)](https://github.com/libre-devops/terraform-azurerm-agfw/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azurerm-agfw)](./LICENSE)

---

## Overview

One Application Gateway v2 per module call, firewalled by default. The gateway and its
`azurerm_web_application_firewall_policy` ship together because a WAF_v2 gateway without a policy
inspects nothing; `sku.tier = "Standard_v2"` and bring-your-own `firewall_policy_id` are both a
line away.

What the module adds over the bare resources:

- **Secure defaults**: WAF_v2 with an auto-created, auto-associated WAF policy (Prevention mode,
  Microsoft Default Rule Set 2.1 plus Bot Manager 1.1, request body inspection), a TLS 1.2 floor
  via the predefined `AppGwSslPolicy20220101` policy, zone-redundant, autoscaling, HTTP/2 on. The
  retired v1 tiers are rejected.
- **Keys, not names**: listeners, pools, settings, probes, rules, redirects, rewrites, and path
  maps are maps cross-referenced by key (`backend_pool_key`, `probe_key`, `listener_key`, ...), so
  renames happen in one place.
- **Derived plumbing**: `frontend_port` blocks are generated from the listeners' ports, and routing
  rule priorities are auto-assigned in key order when not set (explicit priorities win and are
  validated unique).
- **Plan-time truth**: Https listeners must name a certificate, private listeners need the private
  frontend, Basic rules target a backend or a redirect but never both, and `check` blocks warn on
  plain-HTTP listeners, Detection-mode policies, and WAF_v2 without a policy.

The public frontend takes a public ip by id (compose the
[`public-ip`](https://registry.terraform.io/modules/libre-devops/public-ip/azurerm/latest) module);
an optional private frontend pins a static address on the gateway's dedicated subnet. The resource
group is passed by id and parsed.

## Usage

```hcl
module "agfw" {
  source  = "libre-devops/agfw/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids["rg-ldo-uks-prd-001"]
  location          = "uksouth"
  tags              = module.tags.tags

  name                 = "agw-ldo-uks-prd-001"
  gateway_subnet_id    = module.network.subnet_ids["snet-agw-vnet-ldo-uks-prd-001"]
  public_ip_address_id = module.public_ip.public_ip_ids["pip-ldo-uks-prd-001"]

  waf_policy = { name = "waf-ldo-uks-prd-001" }

  backend_pools = { "app" = { ip_addresses = ["10.0.2.10"] } }

  backend_http_settings = {
    "app-https" = { probe_key = "app-health" }
  }

  probes = {
    "app-health" = { protocol = "Https", path = "/healthz" }
  }

  ssl_certificates = {
    "wildcard" = { key_vault_secret_id = module.keyvault.certificate_secret_ids["wildcard"] }
  }

  listeners = {
    "web-https" = { port = 443, protocol = "Https", ssl_certificate_key = "wildcard" }
  }

  request_routing_rules = {
    "web" = {
      listener_key              = "web-https"
      backend_pool_key          = "app"
      backend_http_settings_key = "app-https"
    }
  }
}
```

## Examples

- [`examples/minimal`](./examples/minimal) - a WAF_v2 gateway with the module defaults and a
  single pool, setting, listener, and rule.
- [`examples/complete`](./examples/complete) - the full certificate-free surface: private
  frontend, custom probes, connection draining, rewrite sets, redirects, path-based routing, and a
  tuned WAF policy (overrides, exclusions, rate limiting, geo blocking, log scrubbing).

## Developing

Local work needs **PowerShell 7+** and **[`just`](https://github.com/casey/just)**, because the recipes
wrap the [LibreDevOpsHelpers](https://www.powershellgallery.com/packages/LibreDevOpsHelpers)
PowerShell module (the same engine the `libre-devops/terraform-azure` action runs in CI). Install
just with `brew install just`, or `uv tool add rust-just` then `uv run just <recipe>`.

Run `just` to list recipes: `just update-ldo-pwsh` (install or force-update LibreDevOpsHelpers from
PSGallery), `just validate`, `just scan` (Trivy only), `just pwsh-analyze` (PSScriptAnalyzer only),
`just plan`, `just apply`, `just destroy`, `just e2e`, `just test`, and `just docs` (the
plan/apply/destroy recipes mirror the action, including the storage firewall dance; `just e2e`
applies an example then always destroys it, defaulting to `minimal`, so nothing is left running).
Releasing is also `just`:
`just increment-release [patch|minor|major]` bumps, tags, and publishes a GitHub release, and the
Terraform Registry picks up the tag.

## Security scan exceptions

This module is scanned with [Trivy](https://github.com/aquasecurity/trivy); HIGH and CRITICAL
findings fail the build. Any waiver is a deliberate, reviewed decision, never a way to quiet a
finding that should be fixed. Waivers live in [`.trivyignore.yaml`](./.trivyignore.yaml) (the
machine-applied source of truth, passed to Trivy with `--ignorefile`) and are mirrored in the table
below so the reason is auditable.

| Trivy ID | Resource | Finding | Justification |
|----------|----------|---------|---------------|
| _None_   |          |         |               |

To add an exception: add an entry to `.trivyignore.yaml` (`id`, optional `paths` to scope it, and a
`statement` recording why), then add a matching row here. Where the finding is out of this module's
scope, point the justification at the Libre DevOps module that does address it (for example the
private-endpoint module). Both the file and this table are reviewed in the pull request.

## Reference

The Requirements, Providers, Inputs, Outputs, and Resources below are generated by `terraform-docs`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0.0, < 5.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_application_gateway.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_gateway) | resource |
| [azurerm_web_application_firewall_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/web_application_firewall_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_authentication_certificates"></a> [authentication\_certificates](#input\_authentication\_certificates) | v1-style backend authentication certificates keyed by name (kept for completeness; prefer trusted\_root\_certificates on v2). | <pre>map(object({<br/>    data = string<br/>  }))</pre> | `{}` | no |
| <a name="input_autoscale_configuration"></a> [autoscale\_configuration](#input\_autoscale\_configuration) | Autoscale bounds, on by default (0 to 2 capacity units). Ignored when sku.capacity pins a fixed count. | <pre>object({<br/>    min_capacity = optional(number, 0)<br/>    max_capacity = optional(number, 2)<br/>  })</pre> | `{}` | no |
| <a name="input_backend_http_settings"></a> [backend\_http\_settings](#input\_backend\_http\_settings) | Backend HTTP settings keyed by name. Defaults speak HTTPS to the backend (port 443, protocol Https) with cookie affinity off; probe\_key wires a probe from probes. | <pre>map(object({<br/>    port                                 = optional(number, 443)<br/>    protocol                             = optional(string, "Https")<br/>    cookie_based_affinity                = optional(string, "Disabled")<br/>    affinity_cookie_name                 = optional(string)<br/>    request_timeout                      = optional(number, 30)<br/>    path                                 = optional(string)<br/>    host_name                            = optional(string)<br/>    pick_host_name_from_backend_address  = optional(bool)<br/>    probe_key                            = optional(string)<br/>    trusted_root_certificate_names       = optional(list(string))<br/>    certificate_chain_validation_enabled = optional(bool)<br/>    dedicated_backend_connection_enabled = optional(bool)<br/>    sni_name                             = optional(string)<br/>    sni_validation_enabled               = optional(bool)<br/>    authentication_certificate_names     = optional(list(string), [])<br/>    connection_draining = optional(object({<br/>      enabled           = optional(bool, true)<br/>      drain_timeout_sec = optional(number, 60)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_backend_pools"></a> [backend\_pools](#input\_backend\_pools) | Backend address pools keyed by pool name: FQDNs, ip addresses, or empty for NIC-attached backends. | <pre>map(object({<br/>    fqdns        = optional(list(string))<br/>    ip_addresses = optional(list(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_custom_error_configurations"></a> [custom\_error\_configurations](#input\_custom\_error\_configurations) | Gateway-wide custom error pages: status code to a publicly reachable html url. | <pre>list(object({<br/>    status_code           = string<br/>    custom_error_page_url = string<br/>  }))</pre> | `[]` | no |
| <a name="input_fips_enabled"></a> [fips\_enabled](#input\_fips\_enabled) | Whether FIPS 140-2 mode is enabled. | `bool` | `false` | no |
| <a name="input_firewall_policy_id"></a> [firewall\_policy\_id](#input\_firewall\_policy\_id) | Bring-your-own WAF policy id. Mutually exclusive with the module-created policy (waf\_policy.create). | `string` | `null` | no |
| <a name="input_force_firewall_policy_association"></a> [force\_firewall\_policy\_association](#input\_force\_firewall\_policy\_association) | Whether the WAF policy association is forced during association changes. | `bool` | `true` | no |
| <a name="input_gateway_subnet_id"></a> [gateway\_subnet\_id](#input\_gateway\_subnet\_id) | Subnet the gateway lives in (a dedicated subnet; nothing else may share it). | `string` | n/a | yes |
| <a name="input_global_buffering"></a> [global\_buffering](#input\_global\_buffering) | Gateway-wide request and response buffering toggles. | <pre>object({<br/>    request_buffering_enabled  = optional(bool, true)<br/>    response_buffering_enabled = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_http2_enabled"></a> [http2\_enabled](#input\_http2\_enabled) | Whether HTTP/2 is enabled on the frontends. | `bool` | `true` | no |
| <a name="input_identity"></a> [identity](#input\_identity) | Managed identity for the gateway (a user-assigned identity is required to read Key Vault certificates via key\_vault\_secret\_id). | <pre>object({<br/>    type         = optional(string, "UserAssigned")<br/>    identity_ids = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | HTTP(S) listeners keyed by listener name. frontend picks "public" (default) or "private" (needs<br/>private\_frontend). The frontend port block is derived from port automatically. protocol is an<br/>explicit choice, no default: Https requires ssl\_certificate\_key (or ssl\_certificate\_name for a<br/>certificate managed elsewhere), and Http is flagged by a check as a TLS nudge. | <pre>map(object({<br/>    port                 = number<br/>    protocol             = string<br/>    frontend             = optional(string, "public")<br/>    host_name            = optional(string)<br/>    host_names           = optional(list(string))<br/>    require_sni          = optional(bool)<br/>    ssl_certificate_key  = optional(string)<br/>    ssl_certificate_name = optional(string)<br/>    ssl_profile_key      = optional(string)<br/>    firewall_policy_id   = optional(string)<br/>    custom_error_configurations = optional(list(object({<br/>      status_code           = string<br/>      custom_error_page_url = string<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the gateway. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the application gateway (agw-ldo-uks-prd-001). | `string` | n/a | yes |
| <a name="input_private_frontend"></a> [private\_frontend](#input\_private\_frontend) | Optional "private" frontend on the gateway subnet. private\_ip\_address pins a static address (required by Azure for a v2 private frontend). | <pre>object({<br/>    private_ip_address = string<br/>  })</pre> | `null` | no |
| <a name="input_private_link_configurations"></a> [private\_link\_configurations](#input\_private\_link\_configurations) | Private link configurations keyed by name, enabling Private Endpoint connectivity to the gateway frontends. | <pre>map(object({<br/>    ip_configurations = map(object({<br/>      subnet_id                     = string<br/>      primary                       = bool<br/>      private_ip_address_allocation = optional(string, "Dynamic")<br/>      private_ip_address            = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_probes"></a> [probes](#input\_probes) | Health probes keyed by probe name. protocol defaults to Http; host defaults to picking the backend http settings host (pick\_host\_name\_from\_backend\_http\_settings) unless a host is given. | <pre>map(object({<br/>    protocol                                  = optional(string, "Http")<br/>    path                                      = optional(string, "/")<br/>    host                                      = optional(string)<br/>    pick_host_name_from_backend_http_settings = optional(bool)<br/>    port                                      = optional(number)<br/>    interval                                  = optional(number, 30)<br/>    timeout                                   = optional(number, 30)<br/>    unhealthy_threshold                       = optional(number, 3)<br/>    minimum_servers                           = optional(number)<br/>    proxy_protocol_header_enabled             = optional(bool)<br/>    match = optional(object({<br/>      status_code = list(string)<br/>      body        = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_public_ip_address_id"></a> [public\_ip\_address\_id](#input\_public\_ip\_address\_id) | Standard public ip the "public" frontend fronts (compose the public-ip module). v2 gateways require a public frontend. | `string` | n/a | yes |
| <a name="input_redirect_configurations"></a> [redirect\_configurations](#input\_redirect\_configurations) | Redirect configurations keyed by name: target\_listener\_key redirects to another listener, target\_url to an external url. | <pre>map(object({<br/>    redirect_type        = optional(string, "Permanent")<br/>    target_listener_key  = optional(string)<br/>    target_url           = optional(string)<br/>    include_path         = optional(bool, true)<br/>    include_query_string = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_request_routing_rules"></a> [request\_routing\_rules](#input\_request\_routing\_rules) | Routing rules keyed by rule name. listener\_key picks the listener; a Basic rule targets a<br/>backend (backend\_pool\_key + backend\_http\_settings\_key) or a redirect (redirect\_key); a<br/>PathBasedRouting rule targets a url\_path\_map\_key. priority is optional: unset rules are<br/>auto-assigned 10, 20, 30... in key order (explicit priorities are left alone). | <pre>map(object({<br/>    listener_key              = string<br/>    rule_type                 = optional(string, "Basic")<br/>    priority                  = optional(number)<br/>    backend_pool_key          = optional(string)<br/>    backend_http_settings_key = optional(string)<br/>    redirect_key              = optional(string)<br/>    rewrite_rule_set_key      = optional(string)<br/>    url_path_map_key          = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Resource id of the resource group the gateway is created in. The resource group name and subscription are parsed from this id. | `string` | n/a | yes |
| <a name="input_rewrite_rule_sets"></a> [rewrite\_rule\_sets](#input\_rewrite\_rule\_sets) | Rewrite rule sets keyed by set name; each holds an ordered list of rewrite rules (rule\_sequence decides order). | <pre>map(object({<br/>    rules = list(object({<br/>      name          = string<br/>      rule_sequence = number<br/>      conditions = optional(list(object({<br/>        variable    = string<br/>        pattern     = string<br/>        ignore_case = optional(bool)<br/>        negate      = optional(bool)<br/>      })), [])<br/>      request_header_configurations = optional(list(object({<br/>        header_name  = string<br/>        header_value = string<br/>      })), [])<br/>      response_header_configurations = optional(list(object({<br/>        header_name  = string<br/>        header_value = string<br/>      })), [])<br/>      url = optional(object({<br/>        path         = optional(string)<br/>        query_string = optional(string)<br/>        components   = optional(string)<br/>        reroute      = optional(bool)<br/>      }))<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_sku"></a> [sku](#input\_sku) | Gateway SKU. Only the v2 tiers exist now (v1 Standard/WAF retired April 2026). tier WAF\_v2 (default) or Standard\_v2; name defaults to the tier. capacity pins a fixed instance count and turns off autoscale. | <pre>object({<br/>    tier     = optional(string, "WAF_v2")<br/>    name     = optional(string)<br/>    capacity = optional(number)<br/>  })</pre> | `{}` | no |
| <a name="input_ssl_certificates"></a> [ssl\_certificates](#input\_ssl\_certificates) | TLS certificates keyed by certificate name: inline PFX (data + password) or a Key Vault secret id (needs a user-assigned identity). | <pre>map(object({<br/>    data                = optional(string)<br/>    password            = optional(string)<br/>    key_vault_secret_id = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_ssl_policy"></a> [ssl\_policy](#input\_ssl\_policy) | Gateway-wide TLS policy. Defaults to the predefined AppGwSslPolicy20220101 profile (TLS 1.2 floor with modern ciphers). Set policy\_type Custom/CustomV2 with min\_protocol\_version and cipher\_suites to hand-roll. | <pre>object({<br/>    policy_type          = optional(string, "Predefined")<br/>    policy_name          = optional(string, "AppGwSslPolicy20220101")<br/>    min_protocol_version = optional(string)<br/>    cipher_suites        = optional(list(string))<br/>    disabled_protocols   = optional(list(string))<br/>  })</pre> | `{}` | no |
| <a name="input_ssl_profiles"></a> [ssl\_profiles](#input\_ssl\_profiles) | SSL profiles keyed by profile name, for per-listener mutual TLS and TLS policy overrides. | <pre>map(object({<br/>    trusted_client_certificate_keys      = optional(list(string), [])<br/>    verify_client_certificate_issuer_dn  = optional(bool)<br/>    verify_client_certificate_revocation = optional(string)<br/>    ssl_policy = optional(object({<br/>      policy_type          = optional(string)<br/>      policy_name          = optional(string)<br/>      min_protocol_version = optional(string)<br/>      cipher_suites        = optional(list(string))<br/>      disabled_protocols   = optional(list(string))<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the gateway and its WAF policy. | `map(string)` | `{}` | no |
| <a name="input_trusted_client_certificates"></a> [trusted\_client\_certificates](#input\_trusted\_client\_certificates) | Trusted client CA certificates keyed by name (inline CER data), referenced by ssl profiles for mutual TLS. | <pre>map(object({<br/>    data = string<br/>  }))</pre> | `{}` | no |
| <a name="input_trusted_root_certificates"></a> [trusted\_root\_certificates](#input\_trusted\_root\_certificates) | Trusted root certificates keyed by name (inline CER data or a Key Vault secret id), referenced by backend http settings for backend TLS validation. | <pre>map(object({<br/>    data                = optional(string)<br/>    key_vault_secret_id = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_url_path_maps"></a> [url\_path\_maps](#input\_url\_path\_maps) | URL path maps keyed by map name, for PathBasedRouting rules: a default backend or redirect plus path rules. | <pre>map(object({<br/>    default_backend_pool_key          = optional(string)<br/>    default_backend_http_settings_key = optional(string)<br/>    default_redirect_key              = optional(string)<br/>    default_rewrite_rule_set_key      = optional(string)<br/>    path_rules = map(object({<br/>      paths                     = list(string)<br/>      backend_pool_key          = optional(string)<br/>      backend_http_settings_key = optional(string)<br/>      redirect_key              = optional(string)<br/>      rewrite_rule_set_key      = optional(string)<br/>      firewall_policy_id        = optional(string)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_waf_policy"></a> [waf\_policy](#input\_waf\_policy) | The WAF policy the module creates and associates when sku.tier is WAF\_v2 (ignored on<br/>Standard\_v2). Secure defaults: Prevention mode, Microsoft Default Rule Set 2.1 plus the Bot<br/>Manager rule set 1.1, request body inspection on. Set create = false to bring your own via<br/>firewall\_policy\_id. Fields: name (defaults to waf-<gateway name>), mode, managed\_rule\_sets,<br/>exclusions, custom\_rules (rate limiting, geo blocks, ip allow/deny), and policy\_settings. | <pre>object({<br/>    create = optional(bool, true)<br/>    name   = optional(string)<br/>    mode   = optional(string, "Prevention")<br/><br/>    managed_rule_sets = optional(list(object({<br/>      type    = optional(string, "Microsoft_DefaultRuleSet")<br/>      version = string<br/>      rule_group_overrides = optional(list(object({<br/>        rule_group_name = string<br/>        rules = optional(list(object({<br/>          id      = string<br/>          enabled = optional(bool)<br/>          action  = optional(string)<br/>        })), [])<br/>      })), [])<br/>      })), [<br/>      { type = "Microsoft_DefaultRuleSet", version = "2.1" },<br/>      { type = "Microsoft_BotManagerRuleSet", version = "1.1" },<br/>    ])<br/><br/>    exclusions = optional(list(object({<br/>      match_variable          = string<br/>      selector                = string<br/>      selector_match_operator = string<br/>      excluded_rule_sets = optional(list(object({<br/>        type    = optional(string)<br/>        version = optional(string)<br/>        rule_groups = optional(list(object({<br/>          rule_group_name = string<br/>          excluded_rules  = optional(list(string))<br/>        })), [])<br/>      })), [])<br/>    })), [])<br/><br/>    custom_rules = optional(map(object({<br/>      priority             = number<br/>      rule_type            = optional(string, "MatchRule")<br/>      action               = string<br/>      enabled              = optional(bool)<br/>      rate_limit_duration  = optional(string)<br/>      rate_limit_threshold = optional(number)<br/>      group_rate_limit_by  = optional(string)<br/>      match_conditions = list(object({<br/>        match_variables = list(object({<br/>          variable_name = string<br/>          selector      = optional(string)<br/>        }))<br/>        operator           = string<br/>        match_values       = optional(list(string))<br/>        negation_condition = optional(bool)<br/>        transforms         = optional(list(string))<br/>      }))<br/>    })), {})<br/><br/>    policy_settings = optional(object({<br/>      enabled                                   = optional(bool, true)<br/>      request_body_check                        = optional(bool, true)<br/>      request_body_enforcement                  = optional(bool)<br/>      request_body_inspect_limit_in_kb          = optional(number)<br/>      max_request_body_size_in_kb               = optional(number, 128)<br/>      file_upload_enforcement                   = optional(bool)<br/>      file_upload_limit_in_mb                   = optional(number, 100)<br/>      js_challenge_cookie_expiration_in_minutes = optional(number)<br/>      log_scrubbing = optional(object({<br/>        enabled = optional(bool, true)<br/>        rules = optional(list(object({<br/>          match_variable          = string<br/>          selector                = optional(string)<br/>          selector_match_operator = optional(string)<br/>          enabled                 = optional(bool)<br/>        })), [])<br/>      }))<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_zones"></a> [zones](#input\_zones) | Availability zones the gateway spans. Zone-redundant by default; set [] for regions without zones. | `set(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backend_address_pools"></a> [backend\_address\_pools](#output\_backend\_address\_pools) | Backend address pools as returned by Azure (names and ids), for NIC association composition. |
| <a name="output_backend_pool_ids_zipmap"></a> [backend\_pool\_ids\_zipmap](#output\_backend\_pool\_ids\_zipmap) | Map of backend pool name to a { name, id } object. |
| <a name="output_frontend_ip_configurations"></a> [frontend\_ip\_configurations](#output\_frontend\_ip\_configurations) | Frontend ip configurations as returned by Azure (names, ids, private ip when a private frontend exists). |
| <a name="output_http_listener_ids"></a> [http\_listener\_ids](#output\_http\_listener\_ids) | Map of listener name to its id. |
| <a name="output_id"></a> [id](#output\_id) | Resource id of the application gateway. |
| <a name="output_identity"></a> [identity](#output\_identity) | The gateway's managed identity block, when one is set. |
| <a name="output_name"></a> [name](#output\_name) | Name of the application gateway. |
| <a name="output_private_endpoint_connections"></a> [private\_endpoint\_connections](#output\_private\_endpoint\_connections) | Private endpoint connections on the gateway (populated when private link configurations are used). |
| <a name="output_private_frontend_ip_address"></a> [private\_frontend\_ip\_address](#output\_private\_frontend\_ip\_address) | Static private ip of the private frontend (null when no private frontend). |
| <a name="output_public_frontend_name"></a> [public\_frontend\_name](#output\_public\_frontend\_name) | Name of the public frontend ip configuration (for composing listeners elsewhere). |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group name parsed from resource\_group\_id. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Subscription id parsed from resource\_group\_id. |
| <a name="output_tags"></a> [tags](#output\_tags) | The tags applied to the gateway. |
| <a name="output_waf_policy_id"></a> [waf\_policy\_id](#output\_waf\_policy\_id) | Resource id of the associated WAF policy (module-created or bring-your-own; null on Standard\_v2 without one). |
| <a name="output_waf_policy_name"></a> [waf\_policy\_name](#output\_waf\_policy\_name) | Name of the module-created WAF policy (null when not created here). |
<!-- END_TF_DOCS -->
