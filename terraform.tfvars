libvirt_uri = "qemu+ssh://root@172.16.1.10/system"

el_image = "AlmaLinux-8-GenericCloud-latest.x86_64.qcow2"
coreos_image = "fedora-coreos-35.20220327.3.0-qemu.x86_64.qcow2"

okd_hosts = {
  bootstrap = {
    mac      = "12:22:33:44:55:50"
    vcpus    = 4
    memory   = 16384
    ignition = "bootstrap.ign"
  }

  master1 = {
    mac      = "12:22:33:44:55:51"
    vcpus    = 4
    memory   = 16384
    ignition = "master.ign"
  }

  master2 = {
    mac      = "12:22:33:44:55:52"
    vcpus    = 4
    memory   = 16384
    ignition = "master.ign"
  }

  master3 = {
    mac      = "12:22:33:44:55:53"
    vcpus    = 4
    memory   = 16384
    ignition = "master.ign"
  }

  worker1 = {
    mac      = "12:22:33:44:55:61"
    vcpus    = 4
    memory   = 16384
    ignition = "worker.ign"
  }

  worker2 = {
    mac      = "12:22:33:44:55:62"
    vcpus    = 4
    memory   = 16384
    ignition = "worker.ign"
  }

  worker3 = {
    mac      = "12:22:33:44:55:63"
    vcpus    = 4
    memory   = 16384
    ignition = "worker.ign"
  }
}
