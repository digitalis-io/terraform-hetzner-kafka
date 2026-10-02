# kafka-cluster

Builds the node plan for a KRaft Apache Kafka cluster on Hetzner Cloud. Iteration 1
skeleton: validated inputs and the `nodes` map. Network, servers, volumes and the
Ansible inventory are added by later tickets.

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

## Validation

| Rule | Where |
|------|-------|
| `broker_count` 1..10, `controller_count` null or in {1, 3, 5} | variable validation |
| `ssh_allowed_cidrs` valid CIDRs, no `/0` (`0.0.0.0/0`, `::/0`); empty = no public SSH rule | variable validation |
| `subnet_cidr` valid IPv4, /27 or larger; `network_cidr` valid IPv4 | variable validation |
| `volume_size_gb` 0 or 10..10240; `name` `^[a-z0-9-]{1,40}$` | variable validation |
| Combined mode: `controller_count <= broker_count` | `output.nodes` precondition |
| `subnet_cidr` inside `network_cidr` | `output.nodes` precondition |
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

Or `make module-test` from the repository root. Plan-only, mocked `hcloud`
provider, no credentials needed. Gherkin specifications
live in `tests/compliance/features/` (tagged `@tofu-test`, skipped by
terraform-compliance).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5, < 2.0 |
| <a name="requirement_hcloud"></a> [hcloud](#requirement\_hcloud) | ~> 1.69 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_broker_count"></a> [broker\_count](#input\_broker\_count) | Number of broker nodes, 1 to 10 (one Hetzner spread placement group holds at most 10 servers). | `number` | n/a | yes |
| <a name="input_broker_server_type"></a> [broker\_server\_type](#input\_broker\_server\_type) | Hetzner Cloud server type for broker nodes, for example cpx32. | `string` | n/a | yes |
| <a name="input_controller_count"></a> [controller\_count](#input\_controller\_count) | Number of KRaft controllers (quorum voters): 1, 3, 5, or null for automatic (dedicated mode 3; combined mode 3 when broker\_count >= 3, else 1). In combined mode it must not exceed broker\_count. | `number` | `null` | no |
| <a name="input_controller_server_type"></a> [controller\_server\_type](#input\_controller\_server\_type) | Hetzner Cloud server type for dedicated controller nodes. Ignored in combined mode. Null uses broker\_server\_type. | `string` | `null` | no |
| <a name="input_dedicated_controllers"></a> [dedicated\_controllers](#input\_dedicated\_controllers) | When true, run a separate pool of controller-only nodes; when false, the first controller\_count brokers also act as KRaft controllers. | `bool` | `false` | no |
| <a name="input_image"></a> [image](#input\_image) | Hetzner Cloud image name for every node. | `string` | `"ubuntu-24.04"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Extra Hetzner labels applied to every resource. The module sets cluster, role and managed-by, which take precedence. | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Hetzner Cloud location for every node. One of: fsn1, nbg1, hel1, ash, hil, sin. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Cluster name, used as a prefix for every resource and as the `cluster` label. Lowercase letters, digits and hyphens, 1 to 40 characters. | `string` | n/a | yes |
| <a name="input_network_cidr"></a> [network\_cidr](#input\_network\_cidr) | IPv4 range of the Hetzner private network. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_network_zone"></a> [network\_zone](#input\_network\_zone) | Hetzner network zone of the private subnet. Must contain `location`. One of: eu-central, us-east, us-west, ap-southeast. | `string` | n/a | yes |
| <a name="input_ssh_allowed_cidrs"></a> [ssh\_allowed\_cidrs](#input\_ssh\_allowed\_cidrs) | Source CIDRs allowed to reach SSH (22/tcp) on public interfaces. Empty means no public inbound TCP rule. 0.0.0.0/0 and ::/0 are rejected. | `list(string)` | `[]` | no |
| <a name="input_ssh_key_names"></a> [ssh\_key\_names](#input\_ssh\_key\_names) | Names of SSH keys that already exist in the Hetzner Cloud project. At least one of ssh\_key\_names or ssh\_public\_keys must be set. | `list(string)` | `[]` | no |
| <a name="input_ssh_public_keys"></a> [ssh\_public\_keys](#input\_ssh\_public\_keys) | SSH public keys to create in the project, as a map of key name to OpenSSH public key. At least one of ssh\_key\_names or ssh\_public\_keys must be set. | `map(string)` | `{}` | no |
| <a name="input_subnet_cidr"></a> [subnet\_cidr](#input\_subnet\_cidr) | IPv4 range of the node subnet. Must sit inside network\_cidr and be /27 or larger (nodes use host offsets 10-29). | `string` | `"10.0.1.0/24"` | no |
| <a name="input_volume_size_gb"></a> [volume\_size\_gb](#input\_volume\_size\_gb) | Size in GB of the data volume attached to each broker. 0 uses local disk only; otherwise 10 to 10240. | `number` | `0` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_nodes"></a> [nodes](#output\_nodes) | Map of node key (broker-<n>, controller-<n>) to node attributes: role, node\_id, kafka\_roles, server\_type, private\_ip, has\_volume, labels. |
<!-- END_TF_DOCS -->
