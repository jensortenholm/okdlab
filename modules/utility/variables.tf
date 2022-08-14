variable "base_volume" {
  type        = string
  description = "Terraform id of the libvirt_volume to use as a base for the primary disk (i.e. the EL cloud image)."
}

variable "user_data" {
  type        = string
  description = "Cloudinit user data used to initialize the host."
}

variable "disk_size" {
  type        = number
  description = "Size of the primary disk in bytes."
}

variable "name" {
  type        = string
  description = "Name of this host."
}

variable "memory" {
  type        = number
  description = "Amount of RAM for this host measured in bytes."
}

variable "vcpus" {
  type        = number
  description = "Number of VCPUs to configure for this host."
}

variable "network" {
  type        = string
  description = "Name of the KVM network that this hosts network interface will be attached to."
}

variable "mac" {
  type        = string
  description = "MAC address to configure for this hosts network interface."
}
