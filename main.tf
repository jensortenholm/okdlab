terraform {
  required_version = ">= 1.1"
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "2.1.3"
    }
  }
  experiments = [module_variable_optional_attrs]
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

module "utility" {
  source = "./modules/utility"

  for_each = var.utility_hosts

  base_volume = libvirt_volume.coreos.id
  haproxy_cfg = templatefile("${path.module}/haproxy.conf", {})
  haproxy_svc = templatefile("${path.module}/haproxy.service", {})
  disk_size   = each.value.disk_size
  name        = each.key
  memory      = each.value.memory
  vnc_address = each.value.vnc_address
  vcpus       = each.value.vcpus
  network     = each.value.network
  mac         = each.value.mac
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
