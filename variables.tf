variable "libvirt_uri" {
  type        = string
  description = "Libvirt connection string, for example 'qemu+ssh://root@1.2.3.4/system'."
}

variable "coreos_image" {
  type        = string
  description = "Filename of the QCOW2 CoreOS image to use. Correct image to use needs to be extracted from openshift-install, see README.md."
}

variable "domainname" {
  type        = string
  description = "Cluster domainname, for example clustername.mydomain.tld."
  default     = ""
}

variable "okd_hosts" {
  type = map(object({
    mac         = string
    vcpus       = number
    memory      = number
    ignition    = string
    ip_address  = string
    vnc_address = string
    network     = string
    disk_size   = number
    extra_disks = optional(map(number))
  }))
  description = "Map of OKD hosts to create. Key is used as servername, and each value is another map with host configuration parameters."
}

variable "utility_hosts" {
  type = map(object({
    mac           = string
    vcpus         = number
    memory        = number
    dnsmasq       = optional(bool, false)
    vnc_address   = string
    network       = string
    disk_size     = number
    ip_address    = optional(string)
    network_ip    = optional(string)
    gateway_ip    = optional(string)
    forward_dns   = optional(string, "8.8.8.8")
    haproxy_image = optional(string)
    dnsmasq_image = optional(string)
    ssh_key       = string
    auth          = optional(bool, false)
    registry_name = optional(string)
    registry_user = optional(string)
    registry_pwd  = optional(string)
  }))
  description = "Map of utility hosts to create. Only one host is needed, leave this variable empty if no utility host is to be created. Key is used as servername, value is another map with host configuration parameters."
  default     = {}
}
