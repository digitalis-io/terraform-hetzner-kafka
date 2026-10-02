locals {
  # Hetzner location -> network zone. Lets callers set location only.
  location_network_zone = {
    fsn1 = "eu-central"
    nbg1 = "eu-central"
    hel1 = "eu-central"
    ash  = "us-east"
    hil  = "us-west"
    sin  = "ap-southeast"
  }

  # <project>-<env>; the module appends -<resource> (e.g. kafka-dev-broker-1).
  cluster_name = "${var.name}-${var.environment}"

  # Repo root, where ansible/ansible.cfg expects the inventory (ADR-0002).
  # Relative, so state does not record a machine-specific absolute path.
  inventory_path = "${path.module}/../../inventory.yml"
}
