terraform {
  required_version = ">= 1.3"
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "2.1.3"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

provider "ignition" {
}

resource "libvirt_volume" "coreos" {
  name   = "coreos"
  source = var.coreos_image
}

locals {
  ctlplane = [for k, v in var.okd_hosts : v.ip_address if contains(["master.ign", "bootstrap.ign"], v.ignition)]
  compute = [for k, v in var.okd_hosts : v.ip_address if v.ignition == "worker.ign"]
  all_hosts = {for k, v in var.okd_hosts : k => {ip = v.ip_address, mac = v.mac}}
}

module "utility" {
  source = "./modules/utility"

  for_each = var.utility_hosts

  base_volume   = libvirt_volume.coreos.id
  ctlplane_ips  = local.ctlplane
  compute_ips   = local.compute
  all_hosts     = local.all_hosts
  domainname    = var.domainname
  ip_address    = each.value.ip_address
  forward_dns   = each.value.forward_dns
  network_ip    = each.value.network_ip
  gateway_ip    = each.value.gateway_ip
  dnsmasq       = each.value.dnsmasq
  disk_size     = each.value.disk_size
  name          = each.key
  memory        = each.value.memory
  vnc_address   = each.value.vnc_address
  vcpus         = each.value.vcpus
  network       = each.value.network
  mac           = each.value.mac
  haproxy_image = each.value.haproxy_image
  dnsmasq_image = each.value.dnsmasq_image
  ssh_key       = each.value.ssh_key
  auth          = each.value.auth
  registry_name = each.value.registry_name
  registry_user = each.value.registry_user
  registry_pwd  = each.value.registry_pwd
}

locals {
  unique_ignitions = toset([for k, v in var.okd_hosts : v.ignition])
}

resource "libvirt_ignition" "ignition" {
  for_each = local.unique_ignitions

  name    = each.value
  content = each.value
}

module "okdhosts" {
  source = "./modules/okdhost"

  for_each = var.okd_hosts

  base_volume = libvirt_volume.coreos.id
  ignition_id = libvirt_ignition.ignition[each.value.ignition].id
  name        = each.key
  memory      = each.value.memory
  vcpus       = each.value.vcpus
  vnc_address = each.value.vnc_address
  network     = each.value.network
  mac         = each.value.mac
  disk_size   = each.value.disk_size
  extra_disks = each.value.extra_disks
}
