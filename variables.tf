variable "okd_hosts" {
  type = map(object({
    mac      = string
    vcpus    = number
    memory   = number
    ignition = string
  }))
}
