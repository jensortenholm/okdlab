# Installing OKD 4.10 on KVM using Terraform

## Introduction

This is by no means a polished and secured setup, but rather a quick and dirty solution to spin up OKD clusters in my homelab.

## Environment

In my homelab I have one server running AlmaLinux, with KVM installed. It is connected to my lab network using 2 VLANs, one which I use
for management access of the KVM host itself, and the other is used for the VMs.

My router/firewall serves DHCP and DNS to all my networks, so the necessary customizations of these services for OKD is not included
in this setup, but can be easily added with a dnsmasq configuration on the utility node if needed.

## Preparing the environment

The VMs used consists of one utility server running haproxy loadbalancer, one OKD bootstrap which can be removed once the installation is
done, three OKD master nodes, and three OKD worker nodes. All VMs are installed and configured using terraform (see main.tf).

It is also possible to setup a cluster with only three nodes that act simultaneously as masters and workers, which can be a great option
for a homelab with limited hardware resources.

### DHCP

Static dhcp leases are added to the DHCP server for the necessary VMs. I've used custom MAC addresses on the VMs to make this easier and
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
| Name                           | IP          |
| ------------------------------ | ----------- |
| *.apps.okd4.mylab.mydomain.se  | 172.16.2.40 | 
| api.okd4.mylab.mydomain.se     | 172.16.2.40 |
| api-int.okd4.mylab.mydomain.se | 172.16.2.40 |
------------------------------------------------

## Preparing the installation itself

### Download client, installer and images

Download the okd client and installer from: https://github.com/openshift/okd/releases. You will need the openshift-install package for
the very release that you intend to install, but it is of course possible to update the cluster to newer releases once the install
is done.

To grab the correct fedora coreos image for this particular release, run the installer and grab the image location with jq:

    openshift-install coreos print-stream-json | jq '.architectures.x86_64.artifacts.qemu.formats."qcow2.xz".disk.location'

Then download the image.

The utility machine is built with AlmaLinux cloud image, so download that aswell. Find a local mirror at https://mirrors.almalinux.org.
You will want the GenericCloud image, at the time of writing this it's located in the 8.5/cloud/x86_64/images/ directory of the mirror.

Copy the downloaded images to the directory you plan to run terraform from.

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

### Decompress the images if they are .xz

    xz -d <filename>

### Edit variables

Again, this repository contains two example variable files, one for a three master, three worker node setup (terraform-3workers.yaml) and also
one for a three masters only setup (terraform-onlymasters.yaml).

Copy the file you want to terraform.tfvars and customimze it to your needs, at the very least:

* The libvirt provider URI, to point at your KVM host.
* Update image filenames to what you downloaded.
* Change any IP or MAC addresses that might be different in your environment.
* Change the network name from "newlabnet" to whatever your network is named in KVM.

### Edit cloud_init.cfg

The utility server is configured using cloud-init. As load-balancing is done differently depending on your deployment scenario, this file is
provided in two different versions. One for the three master, three worker node scenario (cloud_init-3workers.cfg), and one for the three
master nodes only scenario (cloud_init-onlymasters.cfg).

Copy the file you want to cloud_init.cfg, and customize it to your needs, updating IP addresses, domainnames, passwords etc.

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

