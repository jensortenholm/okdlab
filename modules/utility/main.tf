terraform {
  required_version = ">= 1.1"
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

resource "libvirt_volume" "disk" {
  name           = "${var.name}.qcow2"
  base_volume_id = var.base_volume
  size           = var.disk_size
}

resource "libvirt_cloudinit_disk" "cloudinit" {
  name           = "cloudinit.iso"
  user_data      = var.user_data
  pool           = "default"
}

resource "libvirt_domain" "host" {
  name            = var.name
  memory          = var.memory
  vcpu            = var.vcpus

  cloudinit = libvirt_cloudinit_disk.cloudinit.id

  qemu_agent = true

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  disk {
    volume_id = libvirt_volume.disk.id
  }

  network_interface {
    network_name   = var.network
    bridge         = var.network
    hostname       = var.name
    mac            = var.mac
    wait_for_lease = true
  }
}
