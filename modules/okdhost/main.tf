terraform {
  required_version = ">= 1.3"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.7"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.3.0"
    }
  }
}

locals {
  disk_objects = var.extra_disks != null ? [
    for name, size in var.extra_disks : {
      source = {
        volume = {
          pool = "images"
          volume = libvirt_volume.extra[name].name
        }
      }
      target = {
        dev = name
        bus = "virtio"
      }
      driver = {
        type = "qcow2"
      }
    }
  ] : []
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

resource "libvirt_volume" "extra" {
  for_each = var.extra_disks != null ? var.extra_disks : {}

  name     = "${var.name}-${each.key}.qcow2"
  pool     = "images"
  capacity = each.value

  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "null_resource" "upload" {
  connection {
    type        = "ssh"
    host        = var.kvm_host_ip
    user        = "root"
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = var.ignition_path
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
            file  = "/var/lib/libvirt/images/${var.name}.ign"
          }
        ]
      }
    }
  ]

  cpu = {
    mode = "host-passthrough"
  }

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
        target = {
          type = "virtio"
          port = 0
        }
      }
    ]

    disks = concat(
      [
        {
          source = {
            volume = {
              pool   = "images"
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
        }
      ],
      local.disk_objects
    )

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

  running = true
}
