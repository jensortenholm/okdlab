# Mirroring OKD release with oc-mirror and mirror-registry

It might be beneficial to keep a local registry with the OKD release containerimages in, especially if you regularly do
cluster installs/uninstalls and/or have limited Internet bandwidth available. To achieve this, three steps are necessary:

1 Deploy an imageregistry to serve the images from.
2 Mirror the OKD release images to your imageregistry.
3 Modify your OKD install-config.yaml to use the local mirror instead of fetching images from the Internet.

Below is a description of one way to do this.

## 1. Setup Redhats mirror-registry

### Install an EL8 host (RHEL/AlmaLinux/RockyLinux/CentOS...)

I usually go for a minimal install, and only add what I need.

### Install podman on the host

    yum -y install podman

### Download mirror-registry to the host

    curl -LO https://developers.redhat.com/content-gateway/file/pub/openshift-v4/clients/mirror-registry/1.2.5/mirror-registry.tar.gz

(Or check https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/ for a newer version)

### Untar the file on the EL8 host

    tar -xf mirror-registry.tar.gz

### Run the installer, substituting password and hostname as appropriate

    ./mirror-registry install --initPassword mysecretpassword --quayHostname myregistry.mydomain.tld

### If you have firewall activated on the host, open up port 8443

    firewall-cmd --add-port=8443/tcp --permament
    firewall-cmd --reload

At this point, a small installation of Quay should be running on the host listening on port 8443. The registry is setup with a selfsigned
certificate, so you will need to add this to the truststore of any clients that will access the registry. The root certificate is available
on the mirrorregistry host in the file /etc/quay-install/quay-rootCA/rootCA.pem.

If you would like to use a proper certificate from your CA of choice instead of the selfsigned certificate, you can provide certificate files
to the mirror-registry installer with the flags --sslCert and --sslKey when you install.

## 2. Mirror OKD release images

This is most easily done with Redhats oc-mirror.

### Download and untar oc-mirror

    tar -xf oc-mirror.tar

### Create an oc-mirror configuration file

To mirror a specific version of the OKD release images, below is an example configuration that does just that, and also stores the
mirroring metadata in your mirror registry. However, oc-mirror can do much more, such as mirroring helm charts, additional images and
operators. For more options, checkout the configuration file specification in https://github.com/openshift/oc-mirror/blob/main/docs/imageset-config-ref.yaml.

Remember to update the version string (minVersion/maxVersion) and adjust the imageURL to the FQDN of your own mirrorregistry host.

    apiVersion: mirror.openshift.io/v1alpha2
    kind: ImageSetConfiguration
    mirror:
      platform:
        channels:
        - name: okd
          type: okd
          minVersion: '4.11.0-0.okd-2022-08-20-022919'
          maxVersion: '4.11.0-0.okd-2022-08-20-022919'
        graph: true
    storageConfig:
      registry:
        imageURL: mirrorregistry.okd4.mylab.mydomain.tld:8443/ocmirror/metadata:latest

### Mirror the release

Before mirrorin gthe release, you need to be logged into your mirrorregistry using the credentials you set when installing mirror-registry:

    podman login mirrorregistry.okd4.mylab.mydomain.tld:8443

Once logged in, do the actual mirroring:

    oc-mirror --config config.yaml docker://mirrorregistry.okd4.mylab.mydomain.tld:8443

This might take a while to download, just sit tight...

Once the mirroring is done, you will find a couple of directories have been created on disk. In oc-mirror-workspace directory, a results
directory is created each time you run the mirroring. It contains amongst other things the ImageContentSourcePolicy configuration, which
is what is used during the installation (and in the installed cluster) to redirect image pulls from their regular locations to the local
mirror.

## 3. Make OKD installation use the mirror

To make the OKD installation process use your local mirror instead of the Internet to download the images, three things need to be changed in
install-config.yaml - the ImageContentSourcePolicy information has to be added, the pull-secret needs to be updated with credentials for your
mirror registry, and the mirror registry CA certificate needs to be added as a trusted CA for the installer to be able to verify it.

For the ImageContentSourcePolicy information, take a peek at the imageContentSourcePolicy.yaml which was created in the results directory
when you ran oc-mirror. Your addition to install-config.yaml will then look something like this (remember to update this to resemble
what oc-mirror created in the results file):

    imageContentSources:
    - mirrors:
      - mirrorregistry.okd4.mylab.mydomain.tld:8443/ubi8
      source: registry.access.redhat.com/ubi8
    - mirrors:
      - mirrorregistry.okd4.mylab.mydomain.tld:8443/openshift/release-images
      source: registry.ci.openshift.org/origin/release
    - mirrors:
      - mirrorregistry.okd4.mylab.mydomain.tld:8443/openshift/release
      source: quay.io/openshift/okd-content
    - mirrors:
      - mirrorregistry.okd4.mylab.mydomain.tld:8443/openshift/release
      source: quay.io/openshift/okd

This configuration essentially says that when the cluster tries to pull images with an image reference starting like what is specified in
source, instead try to pull it from the mirror entry.

The original install-config.yaml example in this repository used a fake pull secret, which works well for pulling images from the Internet.
Your new mirrorregistry will however not be impressed by this, and you will need to change the pull secret to contain credentials for
the mirrorregistry instead.

An updated pull secret in install-config.yaml looks like this:

    pullSecret: '{"auths":{"mirrorregistry.okd4.mylab.mydomain.tld:8443":{"auth":"aW5pdDpteXNlY3JldHBhc3N3b3Jk"}}}'

What looks like a collection of scrambled characters is a base64 encoded string containing the mirrorregistry username (init by default),
followed by a colon, followed by the password you set during mirror-registry installation. You can easily encode this yourself using:

    printf "init:mycustompassword" | base64

And just copy/paste the resulting string. Also, don't forget to update the FQDN of the mirrorregistry host.

To add the trusted CA certificate, copy the contents of /etc/quay/quay-rootCA/rootCA.pem and add it to your install-config.yaml like this:

    additionalTrustBundle: |
      -----BEGIN CERTIFICATE-----
      MIID+zCCAuOgAwIBAgIUBVd1ydYoBzv2gIJWhhJVlYmz4u8wDQYJKoZIhvcNAQEL
      BQAwgYAxCzAJBgNVBAYTAlVTMQswCQYDVQQIDAJWQTERMA8GA1UEBwwITmV3IFlv
      (... etc the rest of the certificate data has been omitted but you should of course include it)
      -----END CERTIFICATE-----

Once this is done, create your manifests and ignitionfiles as usual, and install the cluster. To verify that the installer is actually
using your mirrorregistry instead of pulling from the Internet, the easiest way to do that is to logon to the web interface of mirror-registry
(Quay), click into the organization (for example Openshift) in the right column, click the openshift/release repository and then choose
the bargraph icon in the left column which will show you the usage logs. If images are being pulled from the registry, each pull will count
up in the bargraph shown, and you will also be able to see logs of it at the bottom of that screen.
