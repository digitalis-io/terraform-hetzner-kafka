# Resources are split by concern, all driven by local.nodes:
#   network.tf  - #7 private network and subnet
#   firewall.tf - #7 public-interface firewall (SSH/ICMP allowlist only)
#   ssh.tf      - #8 SSH keys (created and existing)
#   servers.tf  - #8 spread placement groups and servers
#   #9 optional data volumes
