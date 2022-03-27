terraform {
  required_version = ">= 1.1"
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
 }

provider "libvirt" {
  uri = "qemu+ssh://root@172.16.1.10/system"
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

data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  user_data = data.template_file.user_data.rendered
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
  source = "fedora-coreos-35.20220116.2.0-qemu.x86_64.qcow2"
}

resource "libvirt_ignition" "bootstrap_ign" {
  name    = "bootstrap.ign"
  content = "bootstrap.ign"
}

resource "libvirt_ignition" "master_ign" {
  name    = "master.ign"
  content = "master.ign"
}

resource "libvirt_ignition" "worker_ign" {
  name = "worker.ign"
  content = "worker.ign"
}

resource "libvirt_volume" "bootstrap" {
  name           = "bootstrap.qcow2"
  base_volume_id = libvirt_volume.coreos.id
  size           = 107374182400
}

resource "libvirt_volume" "master" {
  count          = 3
  name           = "master${count.index}.qcow2"
  base_volume_id = libvirt_volume.coreos.id
  size           = 107374182400
}

resource "libvirt_volume" "worker" {
  count          = 2
  name           = "worker${count.index}.qcow2"
  base_volume_id = libvirt_volume.coreos.id
  size           = 107374182400
}

resource "libvirt_domain" "bootstrap" {
  name   = "bootstrap"
  memory = "16384"
  vcpu   = 4

  coreos_ignition = libvirt_ignition.bootstrap_ign.id

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "172.16.1.10"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "virtio"
  }

  disk {
    volume_id = libvirt_volume.bootstrap.id
  }

  network_interface {
    network_name   = "newlabnet"
    bridge         = "newlabnet"
    hostname       = "bootstrap"
    mac            = "12:22:33:44:55:50"
  }
}

locals {
  masters = {
    "master1" = { instance = 0, mac = "12:22:33:44:55:51" },
    "master2" = { instance = 1, mac = "12:22:33:44:55:52" },
    "master3" = { instance = 2, mac = "12:22:33:44:55:53" }
  }
  workers = {
    "worker1" = { instance = 0, mac = "12:22:33:44:55:61" },
    "worker2" = { instance = 1, mac = "12:22:33:44:55:62" }
  }
}

resource "libvirt_domain" "masters" {
  for_each = local.masters

  name     = each.key
  memory   = "16384"
  vcpu     = 4

  coreos_ignition = libvirt_ignition.master_ign.id

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "172.16.1.10"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "virtio"
  }

  disk {
    volume_id = libvirt_volume.master[each.value.instance].id
  }

  network_interface {
    network_name = "newlabnet"
    bridge       = "newlabnet"
    hostname     = each.key
    mac          = each.value.mac
  }
}

resource "libvirt_domain" "workers" {
  for_each = local.workers

  name     = each.key
  memory   = "16384"
  vcpu     = 4

  coreos_ignition = libvirt_ignition.worker_ign.id

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "172.16.1.10"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "virtio"
  }

  disk {
    volume_id = libvirt_volume.worker[each.value.instance].id
  }

  network_interface {
    network_name = "newlabnet"
    bridge       = "newlabnet"
    hostname     = each.key
    mac          = each.value.mac
  }
}
