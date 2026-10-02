# Partial S3 backend on Hetzner Object Storage (ADR-0006). Settings come from
# params/<location>/<environment>/backend.hcl via `make prep`; credentials from
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.
terraform {
  backend "s3" {}
}
