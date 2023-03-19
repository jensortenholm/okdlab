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

resource "libvirt_volume" "disk" {
  name           = "${var.name}.qcow2"
  base_volume_id = var.base_volume
  size           = var.disk_size
}

data "ignition_systemd_unit" "haproxy" {
  name    = "haproxy.service"
  content = templatefile("${path.module}/haproxy.service", { haproxy_image = var.haproxy_image })
}

data "ignition_file" "haproxy" {
  path = "/etc/haproxy/haproxy.cfg"
  content {
    // If no compute IPs are specified, this is a cluster with only masters, so use master IPs for workload purposes as well.
    content = templatefile("${path.module}/haproxy.conf.tftpl", { ctlplane = var.ctlplane_ips, compute = length(var.compute_ips) > 0 ? var.compute_ips : var.ctlplane_ips })
  }
}

data "ignition_systemd_unit" "dnsmasq" {
  count   = var.dnsmasq ? 1 : 0
  name    = "dnsmasq.service"
  content = templatefile("${path.module}/dnsmasq.service", { dnsmasq_image = var.dnsmasq_image })
}

data "ignition_file" "dnsmasq" {
  count   = var.dnsmasq ? 1 : 0
  path    = "/etc/dnsmasq.d/dnsmasq.conf"
  content {
    content = templatefile("${path.module}/dnsmasq.conf.tftpl",
      { domainname         = var.domainname,
        ip_address         = var.ip_address,
        forward_dns        = var.forward_dns,
        network_ip         = var.network_ip,
        gateway_ip         = var.gateway_ip
        reverse_ip_address = join(".", reverse(regex("^(\\d+)\\.(\\d+)\\.(\\d+)\\.(\\d+)$", var.ip_address))),
        all_hosts          = var.all_hosts
      }
    )
  }
}

data "ignition_file" "network" {
  count   = var.dnsmasq ? 1 : 0
  path    = "/etc/NetworkManager/system-connections/ens3.nmconnection"
  mode    = 384
  content {
    content = templatefile("${path.module}/nmconnection.tftpl",
      { ip_address  = var.ip_address,
        gateway_ip  = var.gateway_ip,
        hostname    = var.name,
        forward_dns = var.forward_dns
      }
    )
  }
}

data "ignition_file" "sudoers" {
  path = "/etc/sudoers.d/90-admin-user"
  mode = 384
  content {
    content = "admin ALL=(ALL) NOPASSWD:ALL"
  }
}

data "ignition_user" "user" {
  name                = "admin"
  home_dir            = "/home/admin"
  shell               = "/bin/bash"
  groups              = ["wheel"]
  ssh_authorized_keys = [var.ssh_key]
}

data "ignition_config" "utility" {
  systemd = [
    data.ignition_systemd_unit.haproxy.rendered,
    var.dnsmasq ? data.ignition_systemd_unit.dnsmasq[0].rendered : ""
  ]
  files = [
    var.dnsmasq ? data.ignition_file.network[0].rendered : "",
    data.ignition_file.haproxy.rendered,
    data.ignition_file.sudoers.rendered,
    var.dnsmasq ? data.ignition_file.dnsmasq[0].rendered : ""
  ]
  users = [
    data.ignition_user.user.rendered,
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
  
  cpu {
    mode = "host-passthrough"
  }

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
