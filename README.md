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
done, three OKD master nodes, and two OKD worker nodes. All VMs are installed and configured using terraform (see main.tf).

### DHCP

Static dhcp leases are added to the DHCP server for the necessary VMs. I've used custom MAC addresses on the VMs to make this easier and
more predictable.

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

Download the okd client and installer from: https://github.com/openshift/okd/releases

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

Customize it according to your needs (see OKD documentation)

    apiVersion: v1
    baseDomain: mylab.mydomain.se
    compute:
    - hyperthreading: Enabled
      name: worker
      replicas: 2
    controlPlane:
      hyperthreading: Enabled
      name: master
      replicas: 3
    metadata:
      name: okd4
    networking:
      clusterNetwork:
      - cidr: 10.128.0.0/14
        hostPrefix: 23
      networkType: OpenShiftSDN
      serviceNetwork:
      - 172.30.0.0/16
    platform:
      none: {}
    pullSecret: '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}'
    sshKey: <paste contents of okd4.pub here, your public ssh key>

### Run openshift-install

Generate ignition files for the install using the following procedure.

    openshift-install create manifests --dir=.
    openshift-install create ignition-configs --dir=.

The ignitions contains generated certificates with a short expiry for the bootstrap, so this should be done near in time to the installation.

Copy the .ign files to the directory where you plan to run terraform from.

### Decompress the images if they are .xz

    xz -d <filename>

### Edit main.tf

Open up main.tf and terraform.tfvars in your favorite editor, and update the following:

* The libvirt provider URI, to point at your KVM host.
* Update image filenames to what you downloaded.
* Change any IP or MAC addresses that might be different in your environment.
* Change the network name from "newlabnet" to whatever your network is named in KVM.

### Edit cloud_init.cfg

The utility server is configured using cloud-init, so edit the cloud_init.cfg and update IP addresses, domainnames, passwords etc.

## Install

Initialize your terraform directory, to download necessary providers etc:

    terraform init

With these preparations in place, run terraform plan and check that the output looks reasonable:

    terraform plan

If it does, go ahead and start the installation:

    terraform apply

In my lab, the installation took about 45 minutes to complete. For the worker nodes to be added to the cluster, you need to manually approve their CSRs:

    oc get csr

Scan for "Pending" certificates. Then:

    oc adm certificate approve <csr-name>

To uninstall the cluster:

    terraform destroy

