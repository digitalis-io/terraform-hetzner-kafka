# kafka-cluster

Builds a KRaft Apache Kafka cluster on Hetzner Cloud. Current scope: validated
inputs, the `nodes` map, the private network/subnet, an SSH-only public
firewall, SSH keys, spread placement groups, one server per node, optional
broker data volumes and the Ansible inventory.

## Usage

```hcl
module "kafka" {
  source = "../../modules/kafka-cluster"

  name               = "kafka-dev"
  location           = "fsn1"
  network_zone       = "eu-central"
  broker_count       = 3
  broker_server_type = "cpx32"
  ssh_key_names      = ["operator"]
  ssh_allowed_cidrs  = ["203.0.113.10/32"]
}
```

Dedicated controller pool with data volumes:

```hcl
module "kafka" {
  source = "../../modules/kafka-cluster"

  name                   = "kafka-prod"
  location               = "nbg1"
  network_zone           = "eu-central"
  broker_count           = 5
  broker_server_type     = "ccx23"
  dedicated_controllers  = true
  controller_count       = 3
  controller_server_type = "cpx22"
  volume_size_gb         = 200
  ssh_public_keys        = { operator = "ssh-ed25519 AAAA... operator" }
  ssh_allowed_cidrs      = ["198.51.100.0/24"]
  labels                 = { team = "data" }
}
```

## Topology and node IDs

| Mode | Nodes | KRaft roles | Node IDs | Private IP (host offset in `subnet_cidr`) |
|------|-------|-------------|----------|-------------------------------------------|
| Combined (`dedicated_controllers = false`) | `broker-1..N` | first `controller_count`: `[broker, controller]`, rest `[broker]` | 1..N | 10..19 |
| Dedicated (`dedicated_controllers = true`) | `controller-1..C` | `[controller]` | 1..C | 10..14 |
| | `broker-1..N` | `[broker]` | 101..100+N | 20..29 |

`controller_count = null` (default) picks 3 in dedicated mode; in combined mode 3 when
`broker_count >= 3`, otherwise 1. Explicit values must be 1, 3 or 5.

Keys are stable: resizing a pool only adds or removes tail nodes. Changing
controller membership after first boot is unsupported (static KRaft quorum).

## Network and firewall

| Resource | Name | Notes |
|----------|------|-------|
| `hcloud_network` | `<name>-net` | `ip_range = network_cidr` (default `10.0.0.0/16`) |
| `hcloud_network_subnet` | — | `type = "cloud"`, `network_zone`, `ip_range = subnet_cidr` (default `10.0.1.0/24`) |
| `hcloud_firewall` | `<name>-fw` | Inbound 22/tcp and, if `allow_icmp`, ICMP from `ssh_allowed_cidrs` only |

Kafka (9092/9093) is never opened on the public firewall: MVP Kafka is PLAINTEXT
and is reachable only over the private network, which Hetzner firewalls do not
filter (ADR-0004). An empty `ssh_allowed_cidrs` produces a firewall with no
inbound rules, which drops all public inbound traffic. No outbound rules are set,
so egress stays open. Servers attach the firewall through `firewall_ids` using
the `firewall_id` output.

Network and firewall carry the `labels` input plus `cluster = <name>` and
`managed-by = opentofu`.

## Servers, SSH keys and placement groups

| Resource | Name | Notes |
|----------|------|-------|
| `hcloud_ssh_key` | `<name>-<key>` | One per `ssh_public_keys` entry |
| `data.hcloud_ssh_key` | — | One lookup per `ssh_key_names` entry; none when the list is empty |
| `hcloud_placement_group` | `<name>-brokers`, `<name>-controllers` | `type = "spread"` (one physical host per member, max 10). Controllers group only when `dedicated_controllers = true` |
| `hcloud_server` | `<name>-<key>` (e.g. `kafka-dev-broker-1`) | One per `nodes` entry; pool placement group; `firewall_ids = [firewall]`; private IP from `nodes`; public IPv4 and IPv6 on; labels `cluster`, `role`, `managed-by` + `labels` |

- Servers receive every key: `ssh_key_names` first, then created keys (output
  `ssh_keys`). Keys are referenced by name.
- Public IPv4 is required for Ansible SSH and package/agent egress; IPv6 is
  enabled too. Both are behind the SSH-only firewall. Private-only nodes are
  out of MVP scope.
- `lifecycle { ignore_changes = [user_data, image, ssh_keys] }` (ADR-0005):
  changing `image`, cloud-init or keys never rebuilds a Kafka node. Rebuild on
  purpose with `tofu apply -replace='module.kafka.hcloud_server.this["broker-1"]'`;
  rotate keys with Ansible.
- Scaling a pool only adds or removes tail servers; existing servers are not
  changed.
- `user_data` is `null` unless the node has a data volume (see below).
- `ssh_key_names` is read from the Hetzner API during plan, so `plan` needs
  `HCLOUD_TOKEN` with read access even for `-refresh=false` plans.

## Data volumes

`volume_size_gb = 0` (default) keeps Kafka data on the server's local disk.
Any value from 10 to 10240 gives every broker one Hetzner volume (ADR-0005).
Dedicated controllers never get a volume.

| Resource | Name | Notes |
|----------|------|-------|
| `hcloud_volume` | `<name>-<key>-data` (e.g. `kafka-dev-broker-1-data`) | `size = volume_size_gb`, same `location`, `format = "xfs"`, `delete_protection = true`, node labels |
| `hcloud_volume_attachment` | — | Volume to its broker, `automount = false` |

At first boot, cloud-init (`templates/cloud-init.yaml.tftpl`) installs and runs
`/usr/local/sbin/kafka-mount-data-volume` (`templates/mount-data-volume.sh`):

1. Waits up to 120 s for `/dev/disk/by-id/scsi-0HC_Volume_<id>` (the
   attachment is created after the server).
2. Runs `mkfs.xfs` only if `blkid` finds no filesystem. An existing filesystem
   (for example a volume re-attached to a rebuilt server) is never formatted;
   a `blkid` error aborts without formatting.
3. Adds `<device> /var/lib/kafka <fstype> defaults,nofail,x-systemd.device-timeout=30s 0 2` to `/etc/fstab`
   once, then mounts `/var/lib/kafka`.

Output `servers` exposes each node's `volume_id` (`null` without a volume).
Check the result on a node with `findmnt /var/lib/kafka`; failures are in
`/var/log/cloud-init-output.log`.

Design notes:

- The volume is created first without `server_id`, so its device path is known
  when the server is created and written into `user_data`. No disk discovery
  by glob, no dependency cycle: volume -> server -> attachment.
- cloud-init runs only at server creation. Turning volumes on for an existing
  cluster, or editing the template, does not reach running servers
  (`ignore_changes = [user_data]`): the volume is attached but not mounted.
  Rebuild each broker with `tofu apply -replace=...` or mount it by hand.
- Growing `volume_size_gb` resizes the volumes in place; growing the
  filesystem (`xfs_growfs /var/lib/kafka`) is manual. Shrinking is not
  supported by Hetzner.

**Delete protection.** Volumes keep Kafka data through server replacement and
cannot be deleted while protected, so `tofu destroy`, lowering `broker_count`
or changing `location` fails on them. To remove a volume on purpose, first
disable protection (Hetzner Console, or
`hcloud volume disable-protection <name>-<key>-data delete`), then re-run.
Back up anything you need first: deleting a volume deletes its data.

## Ansible inventory

Output `inventory` is a YAML Ansible inventory for the `axonops.axonops`
`kafka` role (ADR-0002). It has no secrets: keep credentials in Ansible Vault.
Write it to disk in the root module and run Ansible as a separate step:

```hcl
resource "local_file" "inventory" {
  content         = module.kafka.inventory
  filename        = "${path.root}/inventory.yml"
  file_permission = "0644"
}
```

Rendered for `name = "kafka-dev"`, `broker_count = 3` (combined mode; trimmed
to one host):

```yaml
"kafka":
  "children":
    "kafka_brokers":
      "hosts":
        "kafka-dev-broker-1": {}
    "kafka_controllers":
      "hosts":
        "kafka-dev-broker-1": {}
  "hosts":
    "kafka-dev-broker-1":
      "ansible_host": "198.51.100.11"
      "ansible_user": "root"
      "kafka_node_id": 1
      "kafka_node_ip": "10.0.1.10"
      "kafka_node_roles":
      - "broker"
      - "controller"
  "vars":
    "kafka_axonops_cluster_name": "kafka-dev"
```

| Key | Value |
|-----|-------|
| host name | server name, `<name>-<key>` |
| `ansible_host` | public IPv4 (SSH) |
| `ansible_user` | `root` |
| `kafka_node_id` | KRaft `node.id` from `nodes` |
| `kafka_node_roles` | KRaft `process.roles`, e.g. `[broker, controller]` |
| `kafka_node_ip` | private IP; Kafka advertises it (never the public IP) |
| `kafka_axonops_cluster_name` | group var, `var.name` |
| `kafka_brokers` / `kafka_controllers` | child groups by KRaft role, for `--limit` and controller-first restarts. The role builds its own groups from `kafka_node_roles` and does not need them |

The YAML is produced with `yamlencode()`, so it is always valid and keys are
sorted (stable diffs). Changing the schema is a breaking change.

Output `bootstrap_servers` is a comma-separated `<private_ip>:9092` list of
every node with the broker role, ordered by node ID, e.g.
`10.0.1.20:9092,10.0.1.21:9092,10.0.1.22:9092` in dedicated mode. It is
reachable only from the private network.

## Validation

| Rule | Where |
|------|-------|
| `broker_count` 1..10, `controller_count` null or in {1, 3, 5} | variable validation |
| `ssh_allowed_cidrs` valid CIDRs, no `/0` (`0.0.0.0/0`, `::/0`); empty = no public SSH rule | variable validation |
| `subnet_cidr` valid IPv4, /27 or larger; `network_cidr` valid IPv4 | variable validation |
| `volume_size_gb` 0 or 10..10240; `name` `^[a-z0-9-]{1,40}$` | variable validation |
| Combined mode: `controller_count <= broker_count` | `output.nodes` precondition |
| `subnet_cidr` inside `network_cidr` | `output.nodes` and `hcloud_network_subnet` preconditions |
| `location` belongs to `network_zone` | `output.nodes` precondition |
| At least one of `ssh_key_names` / `ssh_public_keys` | `output.nodes` precondition |

Cross-variable rules use output preconditions (hard plan failures) so the module
supports OpenTofu/Terraform >= 1.5.

## Tests

```bash
cd modules/kafka-cluster
tofu init -backend=false
tofu test
```

Or `make module-test` from the repository root. `make cloud-init-test` runs
the volume mount script against stubbed `blkid`/`mkfs.xfs`/`mount` (no root,
no real disk). Mocked `hcloud` provider, no credentials needed. Runs are
plan-only except `inventory.tftest.hcl`, which applies against the mock
(public IPv4s are unknown at plan); nothing real is created. Gherkin specifications
live in `tests/compliance/features/`: files tagged `@tofu-test` are realised by
these suites; `network_firewall_policy.feature`, `servers_policy.feature` and
`volumes_policy.feature` run under terraform-compliance against a plan JSON (`make test`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5, < 2.0 |
| <a name="requirement_hcloud"></a> [hcloud](#requirement\_hcloud) | ~> 1.69 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_hcloud"></a> [hcloud](#provider\_hcloud) | 1.69.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [hcloud_firewall.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall) | resource |
| [hcloud_network.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/network) | resource |
| [hcloud_network_subnet.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/network_subnet) | resource |
| [hcloud_placement_group.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/placement_group) | resource |
| [hcloud_server.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/server) | resource |
| [hcloud_ssh_key.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/ssh_key) | resource |
| [hcloud_volume.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/volume) | resource |
| [hcloud_volume_attachment.this](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/volume_attachment) | resource |
| [hcloud_ssh_key.existing](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/data-sources/ssh_key) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_icmp"></a> [allow\_icmp](#input\_allow\_icmp) | When true, allow inbound ICMP (ping) from ssh\_allowed\_cidrs on public interfaces. Has no effect when ssh\_allowed\_cidrs is empty. | `bool` | `true` | no |
| <a name="input_broker_count"></a> [broker\_count](#input\_broker\_count) | Number of broker nodes, 1 to 10 (one Hetzner spread placement group holds at most 10 servers). | `number` | n/a | yes |
| <a name="input_broker_server_type"></a> [broker\_server\_type](#input\_broker\_server\_type) | Hetzner Cloud server type for broker nodes, for example cpx32. | `string` | n/a | yes |
| <a name="input_controller_count"></a> [controller\_count](#input\_controller\_count) | Number of KRaft controllers (quorum voters): 1, 3, 5, or null for automatic (dedicated mode 3; combined mode 3 when broker\_count >= 3, else 1). In combined mode it must not exceed broker\_count. | `number` | `null` | no |
| <a name="input_controller_server_type"></a> [controller\_server\_type](#input\_controller\_server\_type) | Hetzner Cloud server type for dedicated controller nodes. Ignored in combined mode. Null uses broker\_server\_type. | `string` | `null` | no |
| <a name="input_dedicated_controllers"></a> [dedicated\_controllers](#input\_dedicated\_controllers) | When true, run a separate pool of controller-only nodes; when false, the first controller\_count brokers also act as KRaft controllers. | `bool` | `false` | no |
| <a name="input_image"></a> [image](#input\_image) | Hetzner Cloud image name for every node. Applied at creation only; later changes are ignored and do not rebuild servers. | `string` | `"ubuntu-24.04"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Extra Hetzner labels applied to every resource. The module sets cluster, role and managed-by, which take precedence. | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Hetzner Cloud location for every node. One of: fsn1, nbg1, hel1, ash, hil, sin. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Cluster name, used as a prefix for every resource and as the `cluster` label. Lowercase letters, digits and hyphens, 1 to 40 characters. | `string` | n/a | yes |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | IPv4 range of the Hetzner private network. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_network_zone"></a> [network\_zone](#input\_network\_zone) | Hetzner network zone of the private subnet. Must contain `location`. One of: eu-central, us-east, us-west, ap-southeast. | `string` | n/a | yes |
| <a name="input_ssh_allowed_cidrs"></a> [ssh\_allowed\_cidrs](#input\_ssh\_allowed\_cidrs) | Source CIDRs allowed to reach SSH (22/tcp) on public interfaces. Empty means no public inbound TCP rule. Prefixes shorter than /8 (IPv4) or /32 (IPv6), including 0.0.0.0/0 and ::/0, are rejected. | `list(string)` | `[]` | no |
| <a name="input_ssh_key_names"></a> [ssh\_key\_names](#input\_ssh\_key\_names) | Names of SSH keys that already exist in the Hetzner Cloud project. At least one of ssh\_key\_names or ssh\_public\_keys must be set. | `list(string)` | `[]` | no |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | SSH public keys to create in the project, as a map of key name to OpenSSH public key. At least one of ssh\_key\_names or ssh\_public\_keys must be set. | `map(string)` | `{}` | no |
| <a name="input_subnet_cidr"></a> [subnet\_cidr](#input\_subnet\_cidr) | IPv4 range of the node subnet. Must sit inside network\_cidr and be /27 or larger (nodes use host offsets 10-29). | `string` | `"10.0.1.0/24"` | no |
| <a name="input_volume_size_gb"></a> [volume\_size\_gb](#input\_volume\_size\_gb) | Size in GB of the data volume attached to each broker. 0 uses local disk only; otherwise 10 to 10240. | `number` | `0` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bootstrap_servers"></a> [bootstrap\_servers](#output\_bootstrap\_servers) | Comma-separated Kafka bootstrap servers (<private\_ip>:9092) of every node with the broker role, ordered by node ID. Reachable from the private network only. |
| <a name="output_firewall_id"></a> [firewall\_id](#output\_firewall\_id) | ID of the public-interface firewall. Pass to hcloud\_server.firewall\_ids to apply it. |
| <a name="output_inventory"></a> [inventory](#output\_inventory) | Ansible YAML inventory (ADR-0002): group kafka with one host per server (ansible\_host = public IPv4, ansible\_user = root, kafka\_node\_id, kafka\_node\_roles, kafka\_node\_ip = private IP), group var kafka\_axonops\_cluster\_name, and child groups kafka\_brokers / kafka\_controllers. Contains no secrets. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | ID of the Hetzner private network (hcloud\_network). |
| <a name="output_nodes"></a> [nodes](#output\_nodes) | Map of node key (broker-<n>, controller-<n>) to node attributes: role, node\_id, kafka\_roles, server\_type, private\_ip, has\_volume, labels. |
| <a name="output_placement_group_ids"></a> [placement\_group\_ids](#output\_placement\_group\_ids) | Map of pool (broker, controller) to spread placement group ID. controller is present only when dedicated\_controllers = true. |
| <a name="output_servers"></a> [servers](#output\_servers) | Map of node key (broker-<n>, controller-<n>) to server attributes: id, name, public\_ipv4, public\_ipv6, private\_ip, volume\_id (null when the node has no data volume). |
| <a name="output_ssh_keys"></a> [ssh\_keys](#output\_ssh\_keys) | Names of every SSH key injected into the servers: ssh\_key\_names as given, then the keys created from ssh\_public\_keys (<name>-<key>). |
| <a name="output_subnet_id"></a> [subnet\_id](#output\_subnet\_id) | ID of the node subnet (hcloud\_network\_subnet), formatted as NETWORK\_ID-IP\_RANGE. |
<!-- END_TF_DOCS -->
