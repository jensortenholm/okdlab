2023-03-20

* Add example files for setting up OKD as a singlenode cluster.
* Update previous terraform example files with the new, required ssh_key variable for utility nodes.

2023-03-19

* Add support for overriding dnsmasq and haproxy container images on utility host.
* Add admin user on utility host, with sudo privileges and authentication configured with ssh public key.

2022-11-22

* Add support for configuring utility host with dnsmasq for providing DHCP and DNS services on the cluster network.

2022-10-04

* Add HOWTO on how to get started with GitOps using ArgoCD.

2022-09-06

* Generate haproxy configuration from tfvars data using a template instead of copying and editing sample files manually.

2022-09-05

* Use CoreOS instead of AlmaLinux for the utility node, and deploy haproxy as a container.

2022-09-01

* Provide more information on how to configure the KVM host, now using AlmaLinux 9.

2022-08-28

* Add HOWTO on how to get started with CEPH storage using rook in a cluster.

2022-08-25

* Add HOWTO on how to use mirror-registry and oc-mirror to make a local release image mirror for the installs.

* Add CHANGELOG.

2022-08-21

* Provide examples for 3 master 3 worker deployments, as well as 3 masters only deployment.

2022-08-16

* Add some variable validation and update README.

2022-08-14

* Add some variable descriptions and defaults.

2022-08-11

* Make primary disk size configurable by variable, and add support for adding extra disks to OKD hosts.

2022-08-07

* Simplify by using variables and modules in terraform manifests.

2022-03-27

* First version.
