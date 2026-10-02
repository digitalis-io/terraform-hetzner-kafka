variable "name" {
  type        = string
  description = "Cluster name, used as a prefix for every resource and as the `cluster` label. Lowercase letters, digits and hyphens, 1 to 40 characters."

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must match ^[a-z0-9-]{1,40}$."
  }
}

variable "location" {
  type        = string
  description = "Hetzner Cloud location for every node. One of: fsn1, nbg1, hel1, ash, hil, sin."

  validation {
    condition     = contains(["fsn1", "nbg1", "hel1", "ash", "hil", "sin"], var.location)
    error_message = "location must be one of: fsn1, nbg1, hel1, ash, hil, sin."
  }
}

variable "network_zone" {
  type        = string
  description = "Hetzner network zone of the private subnet. Must contain `location`. One of: eu-central, us-east, us-west, ap-southeast."

  validation {
    condition     = contains(["eu-central", "us-east", "us-west", "ap-southeast"], var.network_zone)
    error_message = "network_zone must be one of: eu-central, us-east, us-west, ap-southeast."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "image" {
  # TODO(#8): consumed by hcloud_server.image when servers are added.
  type        = string
  description = "Hetzner Cloud image name for every node."
  default     = "ubuntu-24.04"

  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "image must not be empty."
  }
}

variable "broker_count" {
  type        = number
  description = "Number of broker nodes, 1 to 10 (one Hetzner spread placement group holds at most 10 servers)."

  validation {
    condition     = var.broker_count == floor(var.broker_count) && var.broker_count >= 1 && var.broker_count <= 10
    error_message = "broker_count must be a whole number between 1 and 10."
  }
}

variable "broker_server_type" {
  type        = string
  description = "Hetzner Cloud server type for broker nodes, for example cpx32."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.broker_server_type))
    error_message = "broker_server_type must be a non-empty Hetzner server type name (lowercase letters, digits, hyphens)."
  }
}

variable "dedicated_controllers" {
  type        = bool
  description = "When true, run a separate pool of controller-only nodes; when false, the first controller_count brokers also act as KRaft controllers."
  default     = false
}

variable "controller_count" {
  type        = number
  description = "Number of KRaft controllers (quorum voters): 1, 3, 5, or null for automatic (dedicated mode 3; combined mode 3 when broker_count >= 3, else 1). In combined mode it must not exceed broker_count."
  default     = null

  validation {
    condition     = var.controller_count == null || contains([1, 3, 5], coalesce(var.controller_count, 3))
    error_message = "controller_count must be null or one of 1, 3, 5."
  }
}

variable "controller_server_type" {
  type        = string
  description = "Hetzner Cloud server type for dedicated controller nodes. Ignored in combined mode. Null uses broker_server_type."
  default     = null

  validation {
    condition     = var.controller_server_type == null || can(regex("^[a-z0-9-]+$", coalesce(var.controller_server_type, "x")))
    error_message = "controller_server_type must be null or a Hetzner server type name (lowercase letters, digits, hyphens)."
  }
}

variable "ssh_key_names" {
  type        = list(string)
  description = "Names of SSH keys that already exist in the Hetzner Cloud project. At least one of ssh_key_names or ssh_public_keys must be set."
  default     = []

  validation {
    condition     = alltrue([for k in var.ssh_key_names : length(trimspace(k)) > 0])
    error_message = "ssh_key_names must not contain empty names."
  }
}

variable "ssh_public_keys" {
  type        = map(string)
  description = "SSH public keys to create in the project, as a map of key name to OpenSSH public key. At least one of ssh_key_names or ssh_public_keys must be set."
  default     = {}

  validation {
    condition = alltrue([
      for k in values(var.ssh_public_keys) :
      can(regex("^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\\.com) ", k))
    ])
    error_message = "ssh_public_keys values must be OpenSSH public keys (ssh-ed25519, ssh-rsa, ecdsa-sha2-*, sk-*)."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "ssh_allowed_cidrs" {
  # TODO(#7): consumed by the hcloud_firewall SSH rule.
  type        = list(string)
  description = "Source CIDRs allowed to reach SSH (22/tcp) on public interfaces. Empty means no public inbound TCP rule. 0.0.0.0/0 and ::/0 are rejected."
  default     = []

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ssh_allowed_cidrs must contain only valid CIDRs."
  }

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : !can(regex("/0$", c))])
    error_message = "ssh_allowed_cidrs must not contain 0.0.0.0/0, ::/0 or any other /0 range."
  }
}

variable "network_cidr" {
  type        = string
  description = "IPv4 range of the Hetzner private network."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(regex("^[0-9.]+/[0-9]+$", var.network_cidr)) && can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid IPv4 CIDR, for example 10.0.0.0/16."
  }
}

variable "subnet_cidr" {
  type        = string
  description = "IPv4 range of the node subnet. Must sit inside network_cidr and be /27 or larger (nodes use host offsets 10-29)."
  default     = "10.0.1.0/24"

  validation {
    condition     = can(regex("^[0-9.]+/[0-9]+$", var.subnet_cidr)) && can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR, for example 10.0.1.0/24."
  }

  validation {
    condition     = !can(cidrhost(var.subnet_cidr, 0)) || try(tonumber(split("/", var.subnet_cidr)[1]) <= 27, false)
    error_message = "subnet_cidr must be /27 or larger to fit node host offsets 10-29."
  }
}

variable "volume_size_gb" {
  type        = number
  description = "Size in GB of the data volume attached to each broker. 0 uses local disk only; otherwise 10 to 10240."
  default     = 0

  validation {
    condition     = var.volume_size_gb == floor(var.volume_size_gb) && (var.volume_size_gb == 0 || (var.volume_size_gb >= 10 && var.volume_size_gb <= 10240))
    error_message = "volume_size_gb must be 0 or a whole number between 10 and 10240."
  }
}

variable "labels" {
  type        = map(string)
  description = "Extra Hetzner labels applied to every resource. The module sets cluster, role and managed-by, which take precedence."
  default     = {}

  validation {
    condition = alltrue([
      for v in values(var.labels) : can(regex("^([a-zA-Z0-9]([-_.a-zA-Z0-9]{0,61}[a-zA-Z0-9])?)?$", v))
    ])
    error_message = "labels values must be at most 63 characters, alphanumeric at both ends, with only - _ . inside."
  }
}
