# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
### Added
- `examples/complete`: root config calling `modules/kafka-cluster` as `<name>-<environment>` (network zone derived from `location`), partial `s3` backend, `hcloud` (`HCLOUD_TOKEN`) and `local` providers, `local_file.inventory` writing repo-root `inventory.yml` (`0644`); outputs `nodes`, `servers`, `bootstrap_servers`, `inventory`, `inventory_path`; committed `.terraform.lock.hcl` (linux_amd64, darwin_arm64, darwin_amd64); requires OpenTofu >= 1.10 (#12)
- Makefile targets `inventory` (re-render from `tofu output -raw inventory`), `galaxy`, `ping`, `configure`, `smoke-test`, `lint`; Ansible targets use `ANSIBLE_CONFIG=ansible/ansible.cfg` and fail with "run make apply or make inventory first" without `inventory.yml` (#12)
- Branded root `README.md`: quick start, three examples, configuration/outputs tables, KRaft quorum, destroy, security and state-locking notes (#12)
- CI `tofu validate` for `modules/kafka-cluster` and `examples/complete` (`-backend=false`) (#12)
- `kafka-cluster`: output `inventory`, a YAML Ansible inventory (`templates/inventory.yaml.tftpl` + `yamlencode`): group `kafka` with one host per server (`ansible_host` public IPv4, `ansible_user: root`, `kafka_node_id`, `kafka_node_roles`, `kafka_node_ip` private IP), group var `kafka_axonops_cluster_name`, child groups `kafka_brokers` / `kafka_controllers`; no secrets (#10, ADR-0002)
- Output `bootstrap_servers`: broker `<private_ip>:9092` list ordered by node ID (#10)
- `inventory.tftest.hcl` suite (mock-provider apply) and `inventory.feature` spec: combined, dedicated, no secrets, node-ID ordering with 10 brokers (#10)
- `kafka-cluster`: optional data volume per broker when `volume_size_gb > 0`: `hcloud_volume` (`<name>-<key>-data`, `format = "xfs"`, `delete_protection = true`, same location) and `hcloud_volume_attachment` (`automount = false`); dedicated controllers never get one (#9)
- `templates/cloud-init.yaml.tftpl` + `templates/mount-data-volume.sh`: wait up to 120 s for the volume device, `mkfs.xfs` only when `blkid` finds no filesystem (abort on `blkid` errors), `/etc/fstab` entry with `defaults,nofail`, mount `/var/lib/kafka`; `user_data` set only for nodes with a volume (#9)
- `servers` output gains `volume_id` (`null` without a volume) (#9)
- `volumes.tftest.hcl` suite and `volumes.feature` spec; terraform-compliance `volumes_policy.feature` (delete protection, xfs, no automount, labels); `tests/cloud-init/test_mount_data_volume.sh`, `make cloud-init-test` and CI `cloud-init-test` job (shellcheck, sh, dash) (#9)
- `kafka-cluster`: `hcloud_ssh_key` per `ssh_public_keys` entry (`<name>-<key>`) merged with `data.hcloud_ssh_key` lookups for `ssh_key_names`; spread `hcloud_placement_group` per pool (brokers; controllers in dedicated mode); one `hcloud_server` per node (`<name>-<key>`, firewall, placement group, deterministic private IP, public IPv4/IPv6, `ignore_changes = [user_data, image, ssh_keys]`) (#8)
- Outputs `servers` (id, name, public IPv4/IPv6, private IP per node), `placement_group_ids`, `ssh_keys` (#8)
- `servers.tftest.hcl` suite and `servers.feature` spec (combined, dedicated, SSH key merge, plan-level 3 -> 4 scale-out, no-key rejection); terraform-compliance `servers_policy.feature` (firewall, placement group, network, spread type, `managed-by` labels) (#8)
- `kafka-cluster`: private `hcloud_network` (`<name>-net`) and `cloud` subnet; public `hcloud_firewall` (`<name>-fw`) allowing 22/tcp and optional ICMP (`allow_icmp`, default `true`) from `ssh_allowed_cidrs` only, never 9092/9093; outputs `network_id`, `subnet_id`, `firewall_id` (#7)
- `network_firewall.tftest.hcl` suite and Gherkin specs; first terraform-compliance feature `network_firewall_policy.feature` (no Kafka ports, no `/0` sources, cloud subnet, `managed-by` labels) (#7)
- `modules/kafka-cluster` skeleton: pinned `hetznercloud/hcloud ~> 1.69`, validated inputs, `nodes` map (combined or dedicated KRaft controllers) and `nodes` output (#6)
- Native `tofu test` suites and Gherkin specifications for the node map and input validation (#6)
- `make module-test` and CI `module-test` job; terraform-compliance skips `@tofu-test` features (#6)
- Initial project scaffold bootstrapped from automation/bootstrap
- `params/fsn1/dev/params.tfvars.example` and `backend.hcl.example`: S3 backend on Hetzner Object Storage (ADR-0006, OpenTofu >= 1.10)
- `make test`: terraform-compliance against a `-refresh=false` plan (local backend override) using `tests/compliance/features`
- CI `terraform-compliance` job (skips with a notice until `examples/complete` and `.feature` files exist)
- `LOCK` Makefile variable (default `true`); set `LOCK=false` if Object Storage conditional-write locking is unsupported

### Changed
- `params/fsn1/dev/params.tfvars.example` sets the real example inputs (combined 3 x `cpx32`, 20 GB volumes, placeholder SSH key, documentation CIDR) so the CI compliance plan exercises every policy feature (#12)
- `.gitignore` re-includes `examples/**/.terraform.lock.hcl` (a global ignore otherwise hides it) (#12)
- `make test` and the CI compliance job detect `@tofu-test` on tag lines only; comments mentioning it no longer cause policy features to be skipped (#12)
- Test mock providers pin numeric ids for `hcloud_volume` and `hcloud_server` (consumed by `hcloud_volume_attachment`) (#9)
- CI path filter includes `**/*.tftpl` and `modules/**/*.sh` (#9)
- `image` input is now wired into `hcloud_server` (tflint ignore removed) (#8)
- Test mock providers pin numeric ids for `hcloud_firewall` and `hcloud_placement_group` (#8)
- Makefile retargeted to Hetzner: `LOCATION` (default `fsn1`) replaces `REGION`; params at `params/$(LOCATION)/$(ENVIRONMENT)/`; `prep` passes `-backend-config=.../backend.hcl`; tofu runs in `TF_DIR` (default `examples/complete`)
- Root variables passed as `-var=location` and `-var=environment` (was `region` / `env`)
- `check-env` requires `HCLOUD_TOKEN`; `destroy` requires `CONFIRM=yes`; `plan` now fails on tofu error (exit 1)
- CI: SHA-pinned actions, least-privilege permissions, concurrency group, timeouts; installs tflint and trivy; path filter adds `tests/**` and `ansible/**`

### Removed
- Commented AWS/Azure/GCP plugin blocks from `.tflint.hcl`
