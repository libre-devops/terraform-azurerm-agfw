locals {
  location  = lookup(var.regions, var.loc, "uksouth")
  rg_name   = "rg-${var.short}-${var.loc}-${terraform.workspace}-001"
  vnet_name = "vnet-${var.short}-${var.loc}-${terraform.workspace}-001"
  pip_name  = "pip-${var.short}-${var.loc}-${terraform.workspace}-001"
  agw_name  = "agw-${var.short}-${var.loc}-${terraform.workspace}-001"
  waf_name  = "waf-${var.short}-${var.loc}-${terraform.workspace}-001"
  snet_agw  = "snet-agw-${local.vnet_name}"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "platform@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

# The gateway needs a dedicated subnet.
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

# Minimal call: a WAF_v2 gateway with the module defaults (auto-created Prevention-mode WAF policy
# on the Microsoft Default Rule Set, zone redundancy, autoscale, TLS 1.2 floor), one backend pool,
# one backend setting, and a plain-HTTP listener and rule. TLS needs certificate material, so the
# HTTP listener trips the module's listeners_prefer_tls warning by design, see examples/complete
# for the redirect pattern.
module "agfw" {
  source = "../../"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  name                 = local.agw_name
  gateway_subnet_id    = module.network.subnet_ids[local.snet_agw]
  public_ip_address_id = module.public_ip.public_ip_ids[local.pip_name]

  waf_policy = { name = local.waf_name }

  backend_pools = {
    "app" = { ip_addresses = ["10.0.2.10"] }
  }

  backend_http_settings = {
    "app-http" = { port = 8080, protocol = "Http" }
  }

  listeners = {
    "web-http" = { port = 80, protocol = "Http" }
  }

  request_routing_rules = {
    "web" = {
      listener_key              = "web-http"
      backend_pool_key          = "app"
      backend_http_settings_key = "app-http"
    }
  }
}
