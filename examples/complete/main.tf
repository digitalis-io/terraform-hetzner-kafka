module "kafka" {
  source = "../../modules/kafka-cluster"

  name                   = local.cluster_name
  location               = var.location
  network_zone           = local.location_network_zone[var.location]
  image                  = var.image
  broker_count           = var.broker_count
  broker_server_type     = var.broker_server_type
  dedicated_controllers  = var.dedicated_controllers
  controller_count       = var.controller_count
  controller_server_type = var.controller_server_type
  ssh_key_names          = var.ssh_key_names
  ssh_public_keys        = var.ssh_public_keys
  ssh_allowed_cidrs      = var.ssh_allowed_cidrs
  allow_icmp             = var.allow_icmp
  network_cidr           = var.network_cidr
  subnet_cidr            = var.subnet_cidr
  volume_size_gb         = var.volume_size_gb
  labels                 = merge(var.labels, { environment = var.environment })
}

# Ansible handoff (ADR-0002): connection and topology data only, no secrets.
# Re-render without an apply with `make inventory`.
resource "local_file" "inventory" {
  filename        = local.inventory_path
  content         = module.kafka.inventory
  file_permission = "0644"
}
