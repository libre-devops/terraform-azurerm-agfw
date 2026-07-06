# Post-plan sanity checks: informational (warn), they never fail an apply.

# Plain-HTTP listeners belong in redirects to HTTPS, not as the serving path. TLS needs certificate
# material the module cannot invent, so this is a nudge rather than a validation.
check "listeners_prefer_tls" {
  assert {
    condition     = alltrue([for l in values(var.listeners) : l.protocol == "Https"])
    error_message = "At least one listener speaks plain HTTP: prefer an Https listener (with an ssl_certificate) and keep Http listeners only as redirect sources."
  }
}

# A WAF_v2 gateway without any policy attached inspects nothing. (Config-derived, not the computed
# policy id, so the check is decidable at plan time.)
check "waf_tier_has_policy" {
  assert {
    condition     = var.sku.tier != "WAF_v2" || local.create_waf_policy || var.firewall_policy_id != null
    error_message = "The gateway is WAF_v2 but no WAF policy is attached (waf_policy.create is off and no firewall_policy_id was given)."
  }
}

# Detection mode logs attacks without blocking them; fine for tuning, not an end state.
check "waf_prevention_mode" {
  assert {
    condition     = !local.create_waf_policy || var.waf_policy.mode == "Prevention"
    error_message = "The WAF policy is in Detection mode: attacks are logged but not blocked. Move to Prevention once tuned."
  }
}
