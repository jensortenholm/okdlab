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

resource "libvirt_domain" "host" {
  name            = var.name
  memory          = var.memory
  vcpu            = var.vcpus

  coreos_ignition = var.ignition_id

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = var.vnc_address
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "virtio"
  }

  disk {
    volume_id = libvirt_volume.disk.id
  }

  network_interface {
    network_name = var.network
    bridge       = var.network
    hostname     = var.name
    mac          = var.mac
  }
}
