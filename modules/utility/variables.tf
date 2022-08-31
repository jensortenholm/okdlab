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

  validation {
    condition     = var.disk_size >= 21474836480
    error_message = "The disk_size needs to be atleast 21474836480 bytes (20GB)."
  }
}

variable "name" {
  type        = string
  description = "Name of this host."
}

variable "memory" {
  type        = number
  description = "Amount of RAM for this host measured in bytes."

  validation {
    condition     = var.memory >= 4096
    error_message = "The memory needs to be atleast 4096 kbytes (4GB)."
  }
}

variable "vcpus" {
  type        = number
  description = "Number of VCPUs to configure for this host."

  validation {
    condition     = var.vcpus >= 1
    error_message = "The vcpus needs to be atleast 1."
  }
}

variable "network" {
  type        = string
  description = "Name of the KVM network that this hosts network interface will be attached to."
}

variable "mac" {
  type        = string
  description = "MAC address to configure for this hosts network interface."

  validation {
    condition     = can(regex("^([0-9A-Fa-f]{2}[:]){5}([0-9A-Fa-f]{2})$", var.mac))
    error_message = "The MAC must be a valid MAC-address using colon separation. For example: '01:02:03:04:05:06'."
  }
}

variable "vnc_address" {
  type        = string
  description = "IP address used for the KVM VNC console to listen. Usually the KVM hosts management IP."
}
