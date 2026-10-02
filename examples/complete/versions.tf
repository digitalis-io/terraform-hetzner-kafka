terraform {
  # >= 1.10: the S3 backend uses use_lockfile (conditional writes) for state
  # locking on Hetzner Object Storage (ADR-0006).
  required_version = ">= 1.10, < 2.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.69"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
