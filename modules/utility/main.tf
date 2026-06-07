terraform {
  required_version = ">= 1.3"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.7"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "2.1.3"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.3.0"
    }
  }
}

resource "libvirt_volume" "disk" {
  name           = "${var.name}.qcow2"
  pool           = "images"
  capacity       = var.disk_size

  backing_store = {
    path = var.base_volume_path
    
    format = {
      type = "qcow2"
    }
  }

  target = {
    format = {
      type = "qcow2"
    }
  }
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

data "ignition_file" "auth" {
  count = var.auth ? 1 : 0
  path  = "/root/.config/containers/auth.json"
  mode  = 384
  content {
    content = templatefile("${path.module}/auth.json.tftpl",
      {
        registry_name = var.registry_name,
        registry_user = var.registry_user,
        registry_pwd  = var.registry_pwd
      }
    )
  }
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
    var.dnsmasq ? data.ignition_file.dnsmasq[0].rendered : "",
    var.auth ? data.ignition_file.auth[0].rendered : "",
  ]
  users = [
    data.ignition_user.user.rendered,
  ]
}

resource "libvirt_ignition" "utility" {
  name    = "utility"
  content = data.ignition_config.utility.rendered
}

resource "null_resource" "upload" {
  connection {
    type        = "ssh"
    host        = var.kvm_host_ip
    user        = "root"
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = libvirt_ignition.utility.path
    destination = "/var/lib/libvirt/images/${var.name}.ign"
  }
}

resource "libvirt_domain" "host" {
  name        = var.name
  memory      = var.memory
  memory_unit = "MiB"
  vcpu        = var.vcpus
  type        = "kvm"

  features = {
    acpi = true
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  sys_info = [
    {
      fw_cfg = {
        entry = [
          {
            name  = "opt/com.coreos/config"
            value = ""
            file = "/var/lib/libvirt/images/${var.name}.ign"
          }
        ]
      }
    }
  ]

  devices = {
    graphics = [
      {
        vnc = {
          listeners = [
            {
              address = {
                address = var.vnc_address
              }
            }
          ]
        }
      }
    ]

    consoles = [
      {
        targets = [
          {
            type = "virtio"
            port = 0
          }
        ]
      }
    ]

    disks = [
      {
        source = {
          volume = {
            pool = "images"
            volume = libvirt_volume.disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
    ]

    interfaces = [
      {
        type  = "network"
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = var.network
          }
        }
        mac = {
          address = var.mac
        }
      }
    ]
  }

  cpu = {
    mode = "host-passthrough"
  }

  running = true
}
