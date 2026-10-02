# State backend (ADR-0007). Local state (terraform.tfstate in this directory)
# by default. Remote state is recommended for anything shared or long-lived:
#
#   1. Uncomment the s3 block below.
#   2. cp params/<location>/<env>/backend.hcl.example params/<location>/<env>/backend.hcl
#      and set bucket/key (Hetzner Object Storage or any S3-compatible store).
#   3. export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, then `make plan`.
#
# `make prep` passes backend.hcl to `tofu init` only when the block is active.
terraform {
  # backend "s3" {}
}
