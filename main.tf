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

resource "libvirt_volume" "almalinux" {
  name   = "almalinux"
  source = "AlmaLinux-8-GenericCloud-latest.x86_64.qcow2"
}

resource "libvirt_volume" "utility" {
  name           = "utility.qcow2"
  base_volume_id = libvirt_volume.almalinux.id
  size           = 21474836480
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", {})
  pool      = "default"
}

resource "libvirt_domain" "utility" {
  name   = "utility"
  memory = "4096"
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  qemu_agent = true

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  disk {
    volume_id = libvirt_volume.utility.id
  }

  network_interface {
    network_name   = "newlabnet"
    bridge         = "newlabnet"
    hostname       = "utility"
    mac            = "12:22:33:44:55:30"
    wait_for_lease = true
  }
}

resource "libvirt_volume" "coreos" {
  name   = "coreos"
  source = "fedora-coreos-35.20220327.3.0-qemu.x86_64.qcow2"
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
  vnc_address = "172.16.1.10"
  network     = "newlabnet"
  mac         = each.value.mac
}
