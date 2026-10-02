terraform {
  # Cross-variable checks are enforced with an output precondition (see
  # outputs.tf), not cross-variable `validation` blocks, so 1.5 is sufficient.
  required_version = ">= 1.5, < 2.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
  }
}
