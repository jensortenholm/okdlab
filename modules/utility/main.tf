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
}

resource "libvirt_volume" "disk" {
  name           = "${var.name}.qcow2"
  base_volume_id = var.base_volume
  size           = var.disk_size
}

data "ignition_systemd_unit" "haproxy" {
  name    = "haproxy.service"
  content = var.haproxy_svc
}

data "ignition_file" "haproxy" {
  path = "/etc/haproxy/haproxy.cfg"
  content {
    content = var.haproxy_cfg
  }
}

data "ignition_config" "utility" {
  systemd = [
    data.ignition_systemd_unit.haproxy.rendered,
  ]
  files = [
    data.ignition_file.haproxy.rendered,
  ]
}

resource "libvirt_ignition" "utility" {
  name    = "utility"
  content = data.ignition_config.utility.rendered
}

resource "libvirt_domain" "host" {
  name   = var.name
  memory = var.memory
  vcpu   = var.vcpus

  coreos_ignition = libvirt_ignition.utility.id

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
    network_name   = var.network
    bridge         = var.network
    hostname       = var.name
    mac            = var.mac
  }
}
