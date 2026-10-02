variable "name" {
  type        = string
  description = "Project prefix for the cluster. Combined with environment as <name>-<environment> (e.g. kafka-dev); lowercase letters, digits and hyphens."
  default     = "kafka"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,30}$", var.name))
    error_message = "name must match ^[a-z0-9-]{1,30}$ (leaves room for -<environment> within the module's 40-character limit)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment, passed by the Makefile as -var=environment=$(ENVIRONMENT). One of: dev, staging, prod."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "Hetzner Cloud location, passed by the Makefile as -var=location=$(LOCATION). One of: fsn1, nbg1, hel1, ash, hil, sin."

  validation {
    condition     = contains(["fsn1", "nbg1", "hel1", "ash", "hil", "sin"], var.location)
    error_message = "location must be one of: fsn1, nbg1, hel1, ash, hil, sin."
  }
}

variable "image" {
  type        = string
  description = "Hetzner Cloud image for every node. Applied at creation only."
  default     = "ubuntu-24.04"
}

variable "broker_count" {
  type        = number
  description = "Number of broker nodes, 1 to 10."
  default     = 3

  validation {
    condition     = var.broker_count == floor(var.broker_count) && var.broker_count >= 1 && var.broker_count <= 10
    error_message = "broker_count must be a whole number between 1 and 10."
  }
}

variable "broker_server_type" {
  type        = string
  description = "Hetzner Cloud server type for broker nodes, for example cpx32."
  default     = "cpx32"
}

variable "dedicated_controllers" {
  type        = bool
  description = "When true, run a separate controller-only pool; when false, the first controller_count brokers also act as KRaft controllers."
  default     = false
}

variable "controller_count" {
  type        = number
  description = "Number of KRaft controllers: 1, 3, 5, or null for automatic. Do not change after the first apply (static KRaft quorum)."
  default     = null

  validation {
    condition     = var.controller_count == null || contains([1, 3, 5], coalesce(var.controller_count, 3))
    error_message = "controller_count must be null or one of 1, 3, 5."
  }
}

variable "controller_server_type" {
  type        = string
  description = "Hetzner Cloud server type for dedicated controllers. Null uses broker_server_type; ignored in combined mode."
  default     = null
}

variable "ssh_key_names" {
  type        = list(string)
  description = "Names of SSH keys that already exist in the Hetzner Cloud project. Looked up through the API at plan time, so leave empty for offline plans (CI)."
  default     = []
}

variable "ssh_public_keys" {
  type        = map(string)
  description = "SSH public keys to create in the project, as a map of key name to OpenSSH public key. At least one of ssh_public_keys or ssh_key_names must be set."
  default     = {}
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  description = "Source CIDRs allowed to reach SSH (22/tcp) and ICMP on public interfaces. Empty blocks all public inbound traffic (and Ansible)."
  default     = []
}

variable "allow_icmp" {
  type        = bool
  description = "When true, allow inbound ICMP from ssh_allowed_cidrs."
  default     = true
}

variable "network_cidr" {
  type        = string
  description = "IPv4 range of the Hetzner private network."
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "IPv4 range of the node subnet, inside network_cidr and /27 or larger."
  default     = "10.0.1.0/24"
}

variable "volume_size_gb" {
  type        = number
  description = "Size in GB of the data volume attached to each broker and mounted at /var/lib/kafka. 0 uses local disk only; otherwise 10 to 10240."
  default     = 0
}

variable "labels" {
  type        = map(string)
  description = "Extra Hetzner labels applied to every resource. The example adds environment = <environment>."
  default     = {}
}
