variable "base_volume" {
  type        = string
  description = "Terraform id of the libvirt_volume to use as a base for the primary disk (i.e. the CoreOS image)."
}

variable "ignition_id" {
  type        = string
  description = "Terraform id of the libvirt_ignition used to initialize this particular host."
}

variable "disk_size" {
  type        = number
  description = "Size of primary disk in bytes, where CoreOS will be installed."

  validation {
    condition     = var.disk_size >= 107374182400
    error_message = "The disk_size must be atleast 107374182400 bytes (100GB)."
  }
}

variable "name" {
  type        = string
  description = "Name of the host."
}

variable "memory" {
  type        = number
  description = "Amount of RAM for this host, measured in bytes."

  validation {
    condition     = var.memory >= 8192
    error_message = "The memory must be atleast 8192 (8GB)."
  }
}

variable "vcpus" {
  type        = number
  description = "Amount of VCPUs for this host."

  validation {
    condition     = var.vcpus >= 2
    error_message = "The vcpus must be atleast 2."
  }
}

variable "vnc_address" {
  type        = string
  description = "IP address used for the KVM VNC console to listen. Usually the KVM hosts management IP."
}

variable "network" {
  type        = string
  description = "Name of the KVM network where this hosts virtual NIC is attached."
}

variable "mac" {
  type        = string
  description = "MAC address to configure for this hosts network interface."

  validation {
    condition     = can(regex("^([0-9A-Fa-f]{2}[:]){5}([0-9A-Fa-f]{2})$", var.mac))
    error_message = "The MAC must be a valid MAC-address using colon separation. For example: '01:02:03:04:05:06'."
  }
}

variable "extra_disks" {
  type        = map(number)
  description = "Map of extra disks to attach to the host. Key is used as diskname, and the value is the size of the disk in bytes."
}
