# Getting started with CEPH storage using rook

CEPH (https://ceph.io) is an all-in-one storage system that offers block, file and object storage to the applications in your cluster.
The most convenient way to install and manage it is by using the Rook operator (https://rook.io). This document is a walkthrough on
how to get it running in your cluster.

## Preparation

You will need atleast 3 nodes in your cluster with extra, unused disks attached to them. The terraform manifests in this repository
makes this easy by just adding extra disks to some of your workernodes, for example:

    worker1 = {
      mac         = "12:22:33:44:55:61"
      vcpus       = 4
      memory      = 16384
      ignition    = "worker.ign"
      vnc_address = "172.16.1.10"
      network     = "newlabnet"
      disk_size   = 107374182400
      extra_disks = {
        "extra-0" = 214748364800
      }
    }

Once the cluster is installed, add an extra label to the nodes with these extra disks to confine the rook pods to these nodes, while
also making sure that any other nodes with extra disks won't be picked up by the rook deployment. For example, with workers 1-3 having
extra disks attached intended for storage:

    oc label node worker1.okd4.mylab.mydomain.tld role=storage-node
    oc label node worker2.okd4.mylab.mydomain.tld role=storage-node
    oc label node worker3.okd4.mylab.mydomain.tld role=storage-node

## Installation

This deployment will be based on sample files from the rook git repository, so the first step is to clone it. This command clones the
latest release 1.9.9:

    git clone -b v1.9.9 --single-branch https://github.com/rook/rook

There's a lot of sample files in this repository, so I prefer to make my own install directory and copy the samples I use there before
customizing them.

    mkdir install

As a first step we get things running in the cluster by installing the main components.

    cd install
    cp <rook-clone-dir>/deploy/examples/{crds,common,operator-openshift,cluster}.yaml .

There's a lot of options and comments in these sample files, most of which you do not need to modify for a basic setup like this.

Customize operator-openshift.yaml as follows to add the label used above as a nodeselector to components and to enable discovery.
If the options mentioned are commented in the file, uncomment them and change their values. Keep an eye out for indentation though.

    CSI_PROVISIONER_NODE_AFFINITY: "role=storage-node"
    CSI_PLUGIN_NODE_AFFINITY: "role=storage-node"
    ROOK_ENABLE_DISCOVERY_DAEMON: "true"

Still in operator-openshift.yaml, customize the Deployment-resource by uncommenting and setting the follwoing:

    - name: DISCOVER_AGENT_NODE_AFFINITY
      value: "role=storage-node"

In cluster.yaml, customize the CephCluster-resource by uncommenting spec.placement.all and adjust nodeAffinity:

    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: role
          operator: In
          values:
          - storage-node

Then create the cluster resources:

    oc create -f crds.yaml -f common.yaml -f operator-openshift.yaml -f cluster.yaml

The deployment happens in multiple steps in the namespace rook-ceph, and it might take a while ti discover disks, prepare them for
use, etc. You don't have to wait for this step to complete, but you can move on to configure block, file and object storage.

## Blockstorage

This sample file contains both the CephBlockPool-resource (which sets up the actual block storage pool) and the storageclass
that references it. You don't need to customize it. For more comments and options on the CephBlockPool resource, you can instead
checkout the <rook-clone-dir>/deploy/examples/pool.yaml.

    cp <rook-clone-dir>/deploy/examples/csi/rbd/storageclass.yaml ./block-pool-and-storageclass.yaml
    oc create -f block-pool-and-storageclass.yaml

## Filestorage

Filestorage referes to CephFS, and is common to use with applications where multiple pods need to access the same storage
simultaneously, which is not allowed with blockstorage.

    cp <rook-clone-dir>/deploy/examples/filesystem.yaml .

Update your copy of filesystem.yaml to set nodeaffinity settings on the CephFilesystem resource in spec.metadataServer.placement.nodeAffinity
to match the following:

    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: role
            operator: In
            values:
            - storage-node

Then create the filesystem:

    oc create -f filesystem.yaml

Also, create a storageclass for it:

    cp <rook-clone-dir>/deploy/examples/csi/cephfs/storageclass.yaml ./fs-storageclass.yaml
    oc create -f fs-storageclass.yaml

## Objectstorage

Objectstorage provides S3 compatible storage in the cluster.

    cp <rook-clone-dir>/deploy/examples/object-openshift.yaml .
    oc create -f object-openshift.yaml

Also create a storageclass for it:

    cp <rook-clone-dir>/deploy/exmaples/storageclass-bucket-delete.yaml .
    oc create -f storageclass-bucket-delete.yaml

## Testing

One simple way to test the installation is to create PersistentVolumeClaims and ObjectBucketClaims, and verify that they get Bound status.
If it doesn't get bound immediately after creating it, give it a little time before troubleshooting.

### Testing block storage

    cp <rook-clone-dir>/deploy/examples/csi/rbd/pvc.yaml ./block-pvc.yaml
    oc create -f block-pvc.yaml
    oc describe pvc rbd-pvc

Once done with the test, delete the PVC:

    oc delete pvc rbd-pvc

### Testing file storage

    cp <rook-clone-dir>/deploy/examples/csi/cephfs/pvc.yaml ./file-pvc.yaml
    oc create -f file-pvc.yaml
    oc describe pvc cephfs-pvc

Once done with the test, delete the PVC:

    oc delete pvc cephfs-pvc

### Testing object storage

Objectstorage is tested by a resource type called ObjectBucketClaim, which is essentially the same as a PersistentVolumeClaim but provisions
an ObjectBucket for S3 access, together with a Secret containing the credentials needed to access the bucket.

    cp <rook-clone-dir>/deploy/examples/object-bucket-claim-delete.yaml .
    oc create -f object-bucket-claim-delete.yaml
    oc describe obc ceph-delete-bucket
    oc get secret ceph-delete-bucket

Once done with the test, delete the OBC:

    oc delete obc ceph-delete-bucket

## Setting the block storageclass as default

When deploying other applications which include PVCs, it can be helpful to designate the block storageclass as default, which is what you
want in most cases. Without a default storageclass, each application must specify the storageclass to use in their PVCs. This is controlled
by setting an annotation on the storageclass:

    oc annotate storageclass rook-ceph-block storageclass.kubernetes.io/is-default-class=true
