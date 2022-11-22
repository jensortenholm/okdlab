variable "base_volume" {
  type        = string
  description = "Terraform id of the libvirt_volume to use as a base for the primary disk (i.e. the EL cloud image)."
}

variable "dnsmasq" {
  type        = bool
  description = "Set this to enable dnsmasq container in the utility host."
  default     = false  
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

variable "network_ip" {
  type        = string
  description = "Network IP for the subnet to serve DHCP on. Only used if dnsmasq is activated."
  default     = ""
}

variable "gateway_ip" {
  type        = string
  description = "Network gateway IP (default route). Only used if dnsmasq is activated."
  default     = ""
}

variable "forward_dns" {
  type        = string
  description = "DNS forward server. Only used if dnsmasq is activated."
  default     = ""
}

variable "ctlplane_ips" {
  type        = list
  description = "List of all controlplane node IP addresses."
}

variable "compute_ips" {
  type        = list
  description = "List of all compute node IP addresses."
}

variable "all_hosts" {
  type        = map(object({
    ip  = string
    mac = string
  }))
  description = "Map of all hosts with hostnames as keys and an object with ip and mac as values. Only used if dnsmasq is activated."
}

variable "domainname" {
  type        = string
  description = "The domainname. Only used if dnsmasq is activated."
}

variable "ip_address" {
  type        = string
  description = "The utility host IP address. Only used if dnsmasq is activated."
}
