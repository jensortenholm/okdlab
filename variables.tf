variable "libvirt_uri" {
  type = string
}

variable "el_image" {
  type = string
}

variable "coreos_image" {
  type = string
}

variable "okd_hosts" {
  type = map(object({
    mac         = string
    vcpus       = number
    memory      = number
    ignition    = string
    vnc_address = string
    network     = string
    disk_size   = number
    extra_disks = optional(map(number))
  }))
}

variable "utility_hosts" {
  type = map(object({
    mac       = string
    vcpus     = number
    memory    = number
    disk_size = number
    network   = string
  }))
}
