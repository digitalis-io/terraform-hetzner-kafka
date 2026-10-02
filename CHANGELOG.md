# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
### Fixed
- Hetzner private network NIC stayed DOWN on new servers (Hetzner attaches it after cloud-init configures `eth0`), so KRaft controllers could not reach each other and `createTopics` timed out. Every node's cloud-init now installs `/etc/netplan/60-hetzner-private.yaml` (DHCP on `enp*`) and runs `netplan apply`; `site.yml` applies the same file to existing nodes, asserts `kafka_node_ip` is on the host, and waits for an elected KRaft leader so `make configure` fails instead of passing on a broken quorum (#13)
### Added
- `ansible/`: `requirements.yml` pinning `axonops.axonops` `>=0.6.3,<0.7.0` (Galaxy); `ansible.cfg` (`../inventory.yml` default, SSH `accept-new`, pipelining); `site.yml` (`chrony`, `preflight`, `kafka` roles; replication factors derived from `groups['kafka_brokers']`, not play hosts; pre_tasks assert the inventory contract — `kafka_node_id`/`kafka_node_roles`/`kafka_node_ip` — and that any `/etc/fstab` entry for `/var/lib/kafka` is actually mounted before installing, per #9's `nofail` cloud-init mount); `smoke-test.yml` (produce/consume/delete over private IPs, `block`/`always` cleanup); `group_vars/kafka.yml.example`; `tests/inventory.yml`, `tests/assert-inventory-contract.yml` and `tests/features/configure-cluster.feature` mirroring issue #11's acceptance criteria; `molecule/default/` 3-node combined-cluster scenario (authored and lint/syntax-checked only — not run in this change, no Docker-based molecule run performed); `ansible/README.md`; CI `ansible-lint` job (yamllint, `--syntax-check`, `ansible-lint --profile production`, inventory-contract assertions) (#11)
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
