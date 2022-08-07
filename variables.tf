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
    mac      = string
    vcpus    = number
    memory   = number
    ignition = string
  }))
}
