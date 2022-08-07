terraform {
  required_version = ">= 1.1"
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
 }

provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_volume" "el" {
  name   = "el"
  source = var.el_image
}

module "utility" {
  source      = "./modules/utility"

  for_each    = var.utility_hosts

  base_volume = libvirt_volume.el.id
  user_data   = templatefile("${path.module}/cloud_init.cfg", {})
  disk_size   = each.value.disk_size
  name        = each.key
  memory      = each.value.memory
  vcpus       = each.value.vcpus
  network     = each.value.network
  mac         = each.value.mac
}

resource "libvirt_volume" "coreos" {
  name   = "coreos"
  source = var.coreos_image
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
  source      = "./modules/okdhost"

  for_each    = var.okd_hosts

  base_volume = libvirt_volume.coreos.id
  ignition_id = libvirt_ignition.ignition[each.value.ignition].id
  disk_size   = 107374182400
  name        = each.key
  memory      = each.value.memory
  vcpus       = each.value.vcpus
  vnc_address = each.value.vnc_address
  network     = each.value.network
  mac         = each.value.mac
}
