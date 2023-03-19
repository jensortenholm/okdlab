# Installing OKD 4.12 on KVM using Terraform

## Introduction

This is by no means a polished and secured setup, but rather a quick and dirty solution to spin up OKD clusters in my homelab.

I have tested this method of setting up OKD with versions 4.9, 4.10, 4.11 as well as 4.12.

### Note on 4.12 and mirror-registry

When using mirror-registry as a local repository for OKD 4.12 as described in the release_mirror_with_ocmirror howto, the bootstrap node
fails to pull some images. To work around this, login to the bootstrap node using the ssh key as the core user:

    ssh -i mykey core@bootstrap.clustername.basedomain

Wait until the service release-image-pivot has failed.

    systemctl status release-image-pivot.service

When that happens, a check of its logs reveals that it's lacking access to registry credentials. Install those:

    cp /root/.docker/config.json /etc/ostree/auth.json
    chmod a+r /etc/ostree/auth.json

Then simply start the release-image-pivot.service.

    systemctl start release-image-pivot.service

It should do its work for a while, and your session should disconnect, as it causes the machine to reboot. Then the installation will move forward.

## Environment and KVM host setup

In my homelab I have one server running AlmaLinux 9, with KVM installed. It is connected to my lab network using 2 VLANs, one which I use
for management access of the KVM host itself, and the other is used for the VMs.

The KVM host is based on a minimal install of AlmaLinux 9. The first network interface on the server is configured with the management
VLAN untagged, so the installation picks up its IP address with the default DHCP configuration.

Once the OS is installed and the server has rebooted, a few configurations are needed.

### Virtualization is installed and enabled

    yum -y group install "Virtualization Host"
    yum -y group install "Virtualization Client"
    systemctl enable --now libvirtd

### Configuration of network bridge

A network bridge is needed to connect VMs to the tagged VLAN 10 on the network interface.  Obviously, you'd want to adjust this depending
on how you intend to connect your VMs to the network.

    nmcli connection add type bridge con-name newlabnet ifname newlabnet ipv4.method disabled ipv6.method ignore
    nmcli connection add type vlan con-name vlan10 ifname eno1.10 dev eno1 id 10 master newlabnet slave-type bridge

The bridge also needs to be configured as a libvirt network. Create the file newlabnet.xml:

    <network>
      <name>newlabnet</name>
      <forward mode='bridge'/>
      <bridge name='newlabnet'/>
    </network>

Then configure the network with libvirt:

    virsh net-define newlabnet.xml
    virsh net-start newlabnet
    virsh net-autostart newlabnet

### Configuration of a default storage pool

Create an XML-file pool_default.xml describing the default storage pool, using /var/lib/libvirt/images as the location on disk:

    <pool type='dir'>
      <name>default</name>
      <target>
        <path>/var/lib/libvirt/images</path>
      </target>
    </pool>

Configure the storage pool:

    virsh pool-define pool_default.xml
    virsh pool-start default
    virsh pool-autostart default

## Preparing the environment for OKD

The VMs used consists of one utility server running haproxy loadbalancer and optionally dnsmasq, one OKD bootstrap which can be removed once 
the installation is complete, three OKD master nodes, and three OKD worker nodes. All VMs are installed and configured using terraform (see main.tf).

It is also possible to setup a cluster with only three OKD nodes that act simultaneously as masters and workers, which can be a great option
for a homelab with limited hardware resources.

### DHCP

Persistent dhcp leases are added to the DHCP server for the necessary VMs. I've used custom MAC addresses on the VMs to make this easier and
more predictable. For example, for a full setup of 3 masters and 3 workers:

------------------------------------------------
| Node      | IP          | MAC                |
| ----------| ----------- | -------------------|
| utility   | 172.16.2.40 |  12:22:33:44:55:30 |
| bootstrap | 172.16.2.50 |  12:22:33:44:55:50 |
| master1   | 172.16.2.51 |  12:22:33:44:55:51 |
| master2   | 172.16.2.52 |  12:22:33:44:55:52 |
| master3   | 172.16.2.53 |  12:22:33:44:55:53 |
| worker1   | 172.16.2.61 |  12:22:33:44:55:61 |
| worker2   | 172.16.2.62 |  12:22:33:44:55:62 |
| worker3   | 172.16.2.63 |  12:22:33:44:55:63 |
------------------------------------------------

### DNS

OKD needs forward and reverse name resolution for all the nodes and some special DNS entries which should point at the loadbalancer ip (utility):

------------------------------------------------
| Name                            | IP          |
| ------------------------------- | ----------- |
| *.apps.okd4.mylab.mydomain.tld  | 172.16.2.40 | 
| api.okd4.mylab.mydomain.tld     | 172.16.2.40 |
| api-int.okd4.mylab.mydomain.tld | 172.16.2.40 |
------------------------------------------------

## Preparing the installation itself

### Download client, installer and images

Download the okd client and installer from: https://github.com/okd-project/okd/releases. You will need the openshift-install package for
the very release that you intend to install, but it is of course possible to update the cluster to newer releases once the install
is done.

To grab the correct fedora coreos image for this particular release, run the installer and grab the image location with jq:

    openshift-install coreos print-stream-json | jq '.architectures.x86_64.artifacts.qemu.formats."qcow2.xz".disk.location'

Then download the image.

Copy the downloaded image to the directory you plan to run terraform from.

And also, of course, download and install terraform https://www.terraform.io/downloads

### Setup passwordless ssh

The terraform manifests use a libvirt driver, which needs passwordless ssh to root on the KVM host, so set that up.

    ssh-copy-id root@mykvmserver

### Create an OKD install directory

    mkdir okd4 && cd okd4

### Generate ssh keys for OKD

    ssh-keygen -t ed25519 -N '' -f ./okd4

### Create an install-config.yaml for okd installer

Once you have created this file, you'll likely want to make a backup of it elsewhere. The OKD installer deletes the file when it's done with it...

The repository contains two example files. One for a setup with three master nodes and three worker nodes (install-config-3masters-3workers.yaml),
and also one for a setup with only three master nodes (install-config-only3masters.yaml).

Copy one of the template files to the name install-config.yaml, and customize it to your needs (see OKD documentation).

### Run openshift-install

Generate ignition files for the install using the following procedure.

    openshift-install create manifests --dir=.
    openshift-install create ignition-configs --dir=.

The ignitions contains generated certificates with a short expiry for the bootstrap, so this should be done near in time to the installation.

Copy the .ign files to the directory where you plan to run terraform from.

### Decompress the image if its in .xz format

    xz -d <filename>

### Edit variables

Again, this repository contains example variable files, one for a three master, three worker node setup (terraform-3workers.yaml), one for 
a three masters only setup (terraform-onlymasters.yaml) and one for a three master, three worker node setup where the utility node has dnsmasq
added to provide DNS and DHCP services for the cluster network (terraform-3workers-dnsmasq.yaml).

Copy the file you want to terraform.tfvars and customimze it to your needs, at the very least:

* The libvirt provider URI, to point at your KVM host.
* Update image filenames to what you downloaded.
* Change any IP or MAC addresses that might be different in your environment.
* Change the network name to whatever your network is named in KVM.

## Install

Initialize your terraform directory, to download necessary providers etc:

    terraform init

With these preparations in place, run terraform plan and check that the output looks reasonable:

    terraform plan

If it does, go ahead and start the installation:

    terraform apply

Once the installation gets going (might take a while), you can monitor progress using the openshift client. For example:

    export KUBECONFIG=<your okd directory>/auth/kubeconfig
    oc get clusteroperators
    oc get clusterversion

In my lab, the installation took about 45 minutes to complete. If you have chosen a deployment with both master and worker nodes, you need to manually approve
the worker nodes CSRs towards the end of the installation. The CSRs will come in two "waves", with a second set of CSRs appearing a short while after you have
approved the first set:

    oc get csr

Scan for "Pending" certificates. Then:

    oc adm certificate approve <csr-name>

Or, all of them in one go:

    oc get csr | grep Pending | awk '{print $1}' | xargs -n1 oc adm certificate approve

To uninstall the cluster:

    terraform destroy

