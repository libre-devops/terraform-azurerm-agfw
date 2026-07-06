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
