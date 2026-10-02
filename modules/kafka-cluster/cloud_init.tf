# Per-node cloud-init (#13, ADR-0004/0005). Every node gets a netplan file that
# brings up the Hetzner private network NIC: Hetzner attaches the private
# network after cloud-init has configured eth0, so without it the node has no
# 10.x address and KRaft controllers cannot reach each other. Nodes with a data
# volume also get the mount script (ADR-0005).
#
# hcloud_server ignores user_data changes after creation, so editing this never
# replaces a server; Ansible (site.yml) applies the same netplan file to
# existing nodes.

locals {
  user_data = {
    for k in keys(local.nodes) : k => templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      netplan     = file("${path.module}/templates/netplan-private.yaml")
      device      = try(hcloud_volume.this[k].linux_device, "")
      mount_point = local.kafka_data_dir
      script      = file("${path.module}/templates/mount-data-volume.sh")
    })
  }
}
