variable "libvirt_uri" {
  type        = string
  description = "Libvirt connection string, for example 'qemu+ssh://root@1.2.3.4/system'."
}

variable "el_image" {
  type        = string
  description = "Filename of the EL QCOW2 cloudimage to use for the utility server (requires cloud-init)."
}

variable "coreos_image" {
  type        = string
  description = "Filename of the QCOW2 CoreOS image to use. Correct image to use needs to be extracted from openshift-install, see README.md."
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
  description = "Map of OKD hosts to create. Key is used as servername, and each value is another map with host configuration parameters."
}

variable "utility_hosts" {
  type = map(object({
    mac       = string
    vcpus     = number
    memory    = number
    disk_size = number
    network   = string
  }))
  description = "Map of utility hosts to create. Only one host is needed, leave this variable empty if no utility host is needed. Key is used as servername, value is another map with host configuration parameters."
  default     = {}
}
