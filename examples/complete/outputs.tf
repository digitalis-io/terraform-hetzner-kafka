output "nodes" {
  description = "Map of node key (broker-<n>, controller-<n>) to role, node_id, kafka_roles, server_type, private_ip, has_volume and labels."
  value       = module.kafka.nodes
}

output "servers" {
  description = "Map of node key to server id, name, public_ipv4, public_ipv6, private_ip and volume_id."
  value       = module.kafka.servers
}

output "bootstrap_servers" {
  description = "Comma-separated Kafka bootstrap servers (<private_ip>:9092), reachable from the private network only."
  value       = module.kafka.bootstrap_servers
}

output "inventory" {
  description = "Ansible YAML inventory rendered by the module. No secrets. Used by `make inventory`."
  value       = module.kafka.inventory
}

output "inventory_path" {
  description = "Path of the inventory file written by local_file.inventory, relative to examples/complete (repo root inventory.yml)."
  value       = local_file.inventory.filename
}
