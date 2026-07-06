<!--
  Header for the complete example README. Edit this file, then run `just docs`
  (or ./Sort-LdoTerraform.ps1 -IncludeExamples) to regenerate the section between the markers.
  The example's main.tf is embedded into the README automatically (see .terraform-docs.yml).
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="200">
    </picture>
  </a>
</div>

# Complete example

The full certificate-free surface on one WAF_v2 gateway: public plus private frontends, explicit
autoscale and buffering, ip and fqdn pools, a custom probe with a match block, connection
draining, three rule styles (basic with a security-header rewrite set, redirect to an external
url, and path-based routing), and a tuned WAF policy (rule override, exclusion, per-client rate
limit, geo block, log scrubbing). TLS listeners, ssl profiles, and Key Vault certificates need
certificate material, so the mocked tests cover them instead. The environment comes from the
Terraform workspace (`terraform.workspace`), not a variable. Run it with `just e2e complete`,
which applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
