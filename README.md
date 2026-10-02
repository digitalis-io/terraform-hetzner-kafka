<p align="center">
  <a href="https://digitalis.io">
    <img src="https://digitalis-marketplace-assets.s3.us-east-1.amazonaws.com/DigitalisDigital_DigitalisFullLogoGradient+-+medium.png" alt="Digitalis.IO" width="300">
  </a>
</p>

<p align="center">
  <em>Built and maintained by <a href="https://digitalis.io">Digitalis.IO</a></em>
</p>

# terraform-hetzner-kafka

Provision an Apache Kafka (KRaft) cluster on Hetzner Cloud with OpenTofu, then
install and configure Kafka with the `axonops.axonops` Ansible collection.

- **OpenTofu** creates the private network, an SSH-only firewall, spread
  placement groups, servers, optional data volumes and an Ansible inventory
  (`inventory.yml`).
- **Ansible** (`ansible/`) installs Kafka on those servers and runs a
  produce/consume smoke test.
- **Make** drives the whole lifecycle from the repo root.

Kafka listens on the private network only. Clients must run inside the same
Hetzner network.

## Contents

- [Quick start](#quick-start)
- [Examples](#examples)
- [Make targets](#make-targets)
- [Configuration reference](#configuration-reference)
- [Outputs reference](#outputs-reference)
- [Operations and caveats](#operations-and-caveats)
- [Repository layout](#repository-layout)
- [Contact](#contact)

## Quick start

Requirements: OpenTofu >= 1.10, GNU Make, Ansible, a
Hetzner Cloud project and an Object Storage bucket for state.

```bash
# 1. Credentials (environment only, never in files)
export HCLOUD_TOKEN=<hetzner-cloud-api-token>
export AWS_ACCESS_KEY_ID=<object-storage-access-key>        # S3 state backend
export AWS_SECRET_ACCESS_KEY=<object-storage-secret-key>

# 2. Parameters: edit bucket/key, your SSH public key and your IP
cp params/fsn1/dev/backend.hcl.example   params/fsn1/dev/backend.hcl
cp params/fsn1/dev/params.tfvars.example params/fsn1/dev/params.tfvars
$EDITOR params/fsn1/dev/backend.hcl params/fsn1/dev/params.tfvars

# 3. Infrastructure (writes inventory.yml in the repo root)
make plan  ENVIRONMENT=dev LOCATION=fsn1
make apply ENVIRONMENT=dev LOCATION=fsn1

# 4. Kafka
make galaxy configure smoke-test
```

`make apply` costs money. The default example creates 3 `cpx32` servers and
three 20 GB volumes.

In `params.tfvars`, set at least:

| Setting | Why |
|---------|-----|
| `ssh_public_keys` | The placeholder key is fake; Ansible logs in as `root` with your key |
| `ssh_allowed_cidrs` | Your public IP as `/32`; empty blocks SSH and therefore Ansible |

## Examples

All examples are `params/<location>/<environment>/params.tfvars` files for the
root module in [`examples/complete`](examples/complete). `location` and
`environment` come from `make ... LOCATION=<loc> ENVIRONMENT=<env>`.

### Combined 3-node cluster (dev)

Each node is both broker and KRaft controller. Cheapest production-shaped layout.

```hcl
name               = "kafka"
broker_count       = 3
broker_server_type = "cpx32"

ssh_public_keys   = { operator = "ssh-ed25519 AAAAC3Nza... operator@laptop" }
ssh_allowed_cidrs = ["198.51.100.7/32"]
```

Creates `kafka-dev-broker-1..3` with node IDs 1-3, all in the quorum.

### Dedicated controllers (prod)

Three controller-only nodes hold the quorum; brokers scale independently.

```hcl
name                   = "kafka"
broker_count           = 5
broker_server_type     = "ccx23"
dedicated_controllers  = true
controller_count       = 3
controller_server_type = "cpx22"

ssh_key_names     = ["ops-team"] # keys already in the Hetzner project
ssh_allowed_cidrs = ["198.51.100.0/24"]
labels            = { team = "data", cost-centre = "kafka" }
```

```bash
make plan apply ENVIRONMENT=prod LOCATION=nbg1
```

Creates `kafka-prod-controller-1..3` (IDs 1-3) and `kafka-prod-broker-1..5`
(IDs 101-105).

### Brokers on data volumes

Each broker gets a Hetzner volume, formatted XFS and mounted at
`/var/lib/kafka` by cloud-init. Controllers never get one.

```hcl
name               = "kafka"
broker_count       = 3
broker_server_type = "cpx42"
volume_size_gb     = 500

ssh_public_keys   = { operator = "ssh-ed25519 AAAAC3Nza... operator@laptop" }
ssh_allowed_cidrs = ["198.51.100.7/32"]
```

Volumes are delete-protected; see [Destroying a cluster](#destroying-a-cluster).

## Make targets

Run `make help` for the full list. Common inputs: `ENVIRONMENT` (required for
OpenTofu targets), `LOCATION` (default `fsn1`), `TF_DIR` (default
`examples/complete`).

| Target | What it does |
|--------|--------------|
| `plan` | `tofu init` against the S3 backend, then save a plan to `plan.out` |
| `apply` | Apply the saved plan; writes `inventory.yml` |
| `inventory` | Re-render `inventory.yml` from state (`tofu output -raw inventory`), no apply |
| `galaxy` | `ansible-galaxy collection install -r ansible/requirements.yml` |
| `ping` | `ansible -m ping` against group `kafka` |
| `configure` | `ansible-playbook -i inventory.yml ansible/site.yml` |
| `smoke-test` | `ansible-playbook -i inventory.yml ansible/smoke-test.yml` |
| `test` | terraform-compliance against a `-refresh=false` plan (local backend, no apply) |
| `module-test` | `tofu test` suites for `modules/kafka-cluster` (mocked provider) |
| `cloud-init-test` | Test the volume mount script with stubbed tools |
| `fmt` / `lint` / `docs` | `tofu fmt`, `pre-commit run --all-files`, terraform-docs for the module README |
| `destroy` | Destroy everything; refuses unless `CONFIRM=yes` |

Ansible targets use `ANSIBLE_CONFIG=ansible/ansible.cfg`. `ping`, `configure`
and `smoke-test` fail with `run make apply or make inventory first` when
`inventory.yml` is missing. Pass extra Ansible flags with
`ANSIBLE_OPTS="--limit kafka_controllers"`.

## Configuration reference

Variables of [`examples/complete`](examples/complete). The module accepts the
same inputs plus `name` and `network_zone`; see
[`modules/kafka-cluster/README.md`](modules/kafka-cluster/README.md).

| Variable | Type | Default | Example | Description |
|----------|------|---------|---------|-------------|
| `environment` | `string` | required (Makefile `ENVIRONMENT`) | `"dev"` | One of `dev`, `staging`, `prod` |
| `location` | `string` | required (Makefile `LOCATION`) | `"fsn1"` | `fsn1`, `nbg1`, `hel1`, `ash`, `hil`, `sin`; network zone is derived |
| `name` | `string` | `"kafka"` | `"orders"` | Prefix; resources are `<name>-<environment>-<resource>` |
| `broker_count` | `number` | `3` | `5` | Brokers, 1-10 |
| `broker_server_type` | `string` | `"cpx32"` | `"ccx23"` | Hetzner server type for brokers |
| `dedicated_controllers` | `bool` | `false` | `true` | Separate controller-only pool |
| `controller_count` | `number` | `null` (auto: 3, or 1 if fewer than 3 brokers) | `3` | KRaft voters: 1, 3 or 5 |
| `controller_server_type` | `string` | `null` (= `broker_server_type`) | `"cpx22"` | Server type for dedicated controllers |
| `image` | `string` | `"ubuntu-24.04"` | `"ubuntu-24.04"` | Hetzner image; create-time only |
| `ssh_public_keys` | `map(string)` | `{}` | `{ operator = "ssh-ed25519 AAAA... me@host" }` | Keys to create in the project |
| `ssh_key_names` | `list(string)` | `[]` | `["ops-team"]` | Existing project keys (looked up via API at plan) |
| `ssh_allowed_cidrs` | `list(string)` | `[]` | `["198.51.100.7/32"]` | SSH/ICMP sources; `/0` rejected |
| `allow_icmp` | `bool` | `true` | `false` | Allow ping from `ssh_allowed_cidrs` |
| `network_cidr` | `string` | `"10.0.0.0/16"` | `"10.20.0.0/16"` | Private network range |
| `subnet_cidr` | `string` | `"10.0.1.0/24"` | `"10.20.1.0/24"` | Node subnet, inside `network_cidr`, /27 or larger |
| `volume_size_gb` | `number` | `0` (local disk) | `500` | Data volume per broker, 0 or 10-10240 |
| `labels` | `map(string)` | `{}` | `{ team = "data" }` | Extra labels; `environment` is always added |

At least one of `ssh_public_keys` or `ssh_key_names` is required.

Environment variables:

| Variable | Used by | Example |
|----------|---------|---------|
| `HCLOUD_TOKEN` | hcloud provider | Hetzner Cloud API token (read/write) |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | S3 state backend | Hetzner Object Storage credentials |

## Outputs reference

| Output | Description |
|--------|-------------|
| `nodes` | Node key (`broker-<n>`, `controller-<n>`) to role, node ID, KRaft roles, server type, private IP, volume flag, labels |
| `servers` | Node key to server ID, name, public IPv4/IPv6, private IP, volume ID |
| `bootstrap_servers` | `10.0.1.10:9092,10.0.1.11:9092,...`: brokers on the private network |
| `inventory` | Ansible YAML inventory (no secrets) |
| `inventory_path` | Where `inventory.yml` was written (repo root) |

```bash
tofu -chdir=examples/complete output -raw bootstrap_servers
```

## Operations and caveats

### KRaft quorum is fixed at first boot

The controller set (`controller.quorum.voters`) is static. **Do not change
`controller_count` or `dedicated_controllers` after the first apply.** Doing so
adds or removes voters that the running quorum does not know about and can
leave the cluster without a controller.

With `controller_count = null` the count is derived from `broker_count`
(1 below 3 brokers, otherwise 3), so growing from 1-2 brokers to 3+ changes the
quorum. Set `controller_count` explicitly before the first apply if you expect
to scale. Above that, changing `broker_count` only adds or removes broker-only
tail nodes.

### Destroying a cluster

```bash
make destroy ENVIRONMENT=dev LOCATION=fsn1 CONFIRM=yes
```

Without `CONFIRM=yes` nothing runs. Data volumes have Hetzner delete
protection, so a destroy with `volume_size_gb > 0` fails on the volumes after
removing other resources. Disable protection first, for example with the
[`hcloud` CLI](https://github.com/hetznercloud/cli):

```bash
for v in $(hcloud volume list -o noheader -o columns=name -l cluster=kafka-dev); do
  hcloud volume disable-protection "$v" delete
done
```

Deleting a volume deletes its Kafka data permanently.

### Security

- Kafka uses **PLAINTEXT** listeners on the private network in this release.
  TLS and SASL are planned. Do not route untrusted clients into the network.
- The public firewall opens only SSH (22/tcp) and, optionally, ICMP from
  `ssh_allowed_cidrs`. Kafka ports 9092/9093 are never public.
- Hetzner firewalls do not filter private network traffic; anything in the
  network can reach Kafka.
- `inventory.yml` holds IPs and node IDs only. Secrets belong in Ansible Vault.

### State locking

State lives in Hetzner Object Storage via the S3 backend with
`use_lockfile = true`. Hetzner support for the conditional writes this needs
is unverified. If `plan` or `apply` fails to acquire the lock, run with
`LOCK=false` and make sure only one person or pipeline runs at a time:

```bash
make plan apply ENVIRONMENT=dev LOCK=false
```

## Repository layout

| Path | Contents |
|------|----------|
| `modules/kafka-cluster/` | Reusable module ([README](modules/kafka-cluster/README.md)) |
| `examples/complete/` | Root configuration used by the Makefile |
| `params/<location>/<env>/` | `params.tfvars` and `backend.hcl` per environment (`.example` templates committed) |
| `ansible/` | `ansible.cfg`, `requirements.yml`, `site.yml`, `smoke-test.yml`, `group_vars/` |
| `tests/compliance/features/` | Gherkin specs: terraform-compliance policies and `@tofu-test` specs |
| `docs/` | [Architecture](docs/architecture.md) and ADRs |

## Contact

This project is maintained by [Digitalis.io](https://digitalis.io). For support, visit [digitalis.io/contact](https://digitalis.io/contact).
