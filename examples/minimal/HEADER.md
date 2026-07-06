<!--
  Header for the minimal example README. Edit this file, then run `just docs`
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

# Minimal example

The smallest valid call to this module: a WAF_v2 gateway on a fresh vnet and public ip, with the
module defaults (auto-created Prevention-mode WAF policy, zone redundancy, autoscale, TLS 1.2
floor) and a single pool, setting, listener, and rule. The listener speaks plain HTTP because TLS
needs certificate material, so the module's listeners_prefer_tls check warns by design. The
environment comes from the Terraform workspace (`terraform.workspace`), not a variable. Run it
with `just e2e minimal`, which applies the stack then always destroys it.

[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
