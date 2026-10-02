# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
### Added
- `modules/kafka-cluster` skeleton: pinned `hetznercloud/hcloud ~> 1.69`, validated inputs, `nodes` map (combined or dedicated KRaft controllers) and `nodes` output (#6)
- Native `tofu test` suites and Gherkin specifications for the node map and input validation (#6)
- `make module-test` and CI `module-test` job; terraform-compliance skips `@tofu-test` features (#6)
- Initial project scaffold bootstrapped from automation/bootstrap
- `params/fsn1/dev/params.tfvars.example` and `backend.hcl.example`: S3 backend on Hetzner Object Storage (ADR-0006, OpenTofu >= 1.10)
- `make test`: terraform-compliance against a `-refresh=false` plan (local backend override) using `tests/compliance/features`
- CI `terraform-compliance` job (skips with a notice until `examples/complete` and `.feature` files exist)
- `LOCK` Makefile variable (default `true`); set `LOCK=false` if Object Storage conditional-write locking is unsupported

### Changed
- Makefile retargeted to Hetzner: `LOCATION` (default `fsn1`) replaces `REGION`; params at `params/$(LOCATION)/$(ENVIRONMENT)/`; `prep` passes `-backend-config=.../backend.hcl`; tofu runs in `TF_DIR` (default `examples/complete`)
- Root variables passed as `-var=location` and `-var=environment` (was `region` / `env`)
- `check-env` requires `HCLOUD_TOKEN`; `destroy` requires `CONFIRM=yes`; `plan` now fails on tofu error (exit 1)
- CI: SHA-pinned actions, least-privilege permissions, concurrency group, timeouts; installs tflint and trivy; path filter adds `tests/**` and `ansible/**`

### Removed
- Commented AWS/Azure/GCP plugin blocks from `.tflint.hcl`
