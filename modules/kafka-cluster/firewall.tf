# Public-interface firewall applied to every node via firewall_ids (#8).
# Inbound allowlist only (ADR-0004): 22/tcp and, optionally, ICMP from
# var.ssh_allowed_cidrs. There is deliberately no rule for Kafka (9092/9093):
# MVP Kafka is PLAINTEXT and must stay on the private network. With an empty
# allowlist the firewall has no inbound rules, so all public inbound traffic
# is dropped. Outbound is unrestricted (no `out` rules), which Hetzner treats
# as allow-all, so nodes keep package/agent egress.
resource "hcloud_firewall" "this" {
  name   = "${var.name}-fw"
  labels = local.base_labels

  dynamic "rule" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []

    content {
      description = "SSH from allowlisted CIDRs"
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = var.ssh_allowed_cidrs
    }
  }

  dynamic "rule" {
    for_each = var.allow_icmp && length(var.ssh_allowed_cidrs) > 0 ? [1] : []

    content {
      description = "ICMP from allowlisted CIDRs"
      direction   = "in"
      protocol    = "icmp"
      source_ips  = var.ssh_allowed_cidrs
    }
  }
}
