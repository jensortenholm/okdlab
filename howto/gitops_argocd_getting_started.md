# Getting started with GitOps and ArgoCD

GitOps can be briefly described as the practice of managing your configurations and deployments through manifests checked into a
git repository rather than using regular CLI/GUI tools to do the job. This has a number of advantages, such as being able to trace
changes in configuration through the git history and keeping common configurations for multiple clusters consistent, etc.

This document describes a basic setup using ArgoCD and Kustomize together with SealedSecrets to manage OKD cluster configuration
in this fashion. It takes a lot of inspiration from Christian Hernandez ebook "The Path to GitOps", which is available as a free
download through RedHats developer program (https://developers.redhat.com).

## Tools used

ArgoCD is the tool that monitors one or more git repositories for kubernetes resources, and applies them to the cluster. It does
this regularly, so any changes or additions made in git are subsequently applied to the cluster. ArgoCD will also monitor the
resources in the cluster, and if they change for any reason it will restore them to the configuration as defined in the git
repository.

Kustomize is a tool that processes kubernetes manifests and allows adding, removing or changing resources in them before applying
the resources in a cluster, without changing the original manifest files. It is commonly used to adapt a shared "master" manifest
to the environment it deploys in, such as overriding names of objects, which imageregistry to pull from etc. It also has builtin
functionality to render helm charts (using helm), and then apply kustomize patches to the results before applying the resources
in the cluster.

SealedSecrets makes it possible to encrypt kubernetes Secret resources in advance, and put them in the git repository as an
encrypted SealedSecret resource. Encryption is made by the user with the public part of a keypair, and decryption is made with
the private key which is installed in the cluster together with the SealedSecrets controller. When a user or tool (such as ArgoCD)
creates a SealedSecret resource in the cluster, the controller will react and use the private key to decrypt that resource into
a regular kubernetes Secret. This protects sensitive Secrets at rest in the git repository from being glanced by users with
read access to that repository.

## Preparing the repository

Starting in an empty git repository directory, create the following directory structure:

    .
    ├── bootstrap
    ├── components
    │   ├── applicationsets
    │   ├── appprojects
    │   └── repositories
    └── config

These directories will be used as follows:

* bootstrap directory will contain resources that install and configure the deployments of ArgoCD and SealedSecrets in the
  cluster.
* components directory and its subdirectories will contain ArgoCD resources to create ApplicationSet, AppProject and
  git repository secrets respectively for ArgoCD.
* config directory is a base directory where we will create subdirectories for different cluster components that ArgoCD
  will manage. In those subdirectories, plain kubernetes resources or kustomized resources manifest files will be created.

## Preparing for SealedSecrets

Normally when deploying SealedSecrets into a cluster, the new deployment of the controller will generate its own public and
private certificates, which are used to encrypt and decrypt SealedSecrets. To be able to bootstrap ArgoCD in a freshly
installed cluster, and have that ArgoCD instance fetch its configurations from a private git repository, authentication
credentials needs to be provided for the git repository.

This creates a chicken-and-egg problem, where access to the public key is needed to be able to encrypt the resource with
git repository credentials before the SealedSecrets controller has been deployed (and generated its public/private keypair).
The solution is to manually generate this keypair, and use the public part to encrypt any resources for this repository
that needs protecting. The private key is then created in the cluster before the deployment of the controller, which will
recognize it and be able to use it to decrypt the SealedSecret resources created from the repository.

The private key generated needs to be protected like the master password it is. After creating it in a cluster, it should
not be left laying around, but stored securely by other means.

The keypair is generated with the following command:

    openssl req -x509 -nodes -newkey rsa:4096 -out ss.pem -keyout ss.key -subj "/CN=sealed-secret/O=sealed-secret"

This creates the file ss.pem containing the public key, and ss.key, containing the private key. These needs to be created
in the cluster before applying the bootstrap, and to be able to do that they need to be converted into a kubernetes
Secret resource:

    oc create secret tls -n kube-system --dry-run=client --cert=ss.pem --key=ss.key ss -o yaml | oc label --dry-run=client --local -f /dev/stdin sealedsecrets.bitnami.com/sealed-secrets-key=active -o yaml > ss-keys.yaml

The command above creates a kubernetes Secret containing the public and private certificates, and then adds the
sealedsecrets.bitnami.com/sealed-secret-key=active label to it, which makes the SealedSecrets controller able to find it
in the cluster. The resulting secret is stored in the ss-keys.yaml file.

Note that ss-keys.yaml contains the private key, so this file also needs to be protected.

## Creating content in bootstrap

First of all, we need some resources in the bootstrap directory that will install the ArgoCD operator into the cluster.
The ArgoCD operator is available in the community catalog, but for whatever reason installations from that catalog is
not possible in OKD unless you disable the RedHat catalogs containing licensed Openshift operators. So let's disable
them using the OperatorHub resource:

operatorhub.yaml:

    apiVersion: config.openshift.io/v1
    kind: OperatorHub
    metadata:
      annotations:
        capability.openshift.io/name: marketplace
        include.release.openshift.io/ibm-cloud-managed: "true"
        include.release.openshift.io/self-managed-high-availability: "true"
        include.release.openshift.io/single-node-developer: "true"
        release.openshift.io/create-only: "true"
      name: cluster
    spec:
      sources:
      - name: certified-operators
        disabled: true
      - name: redhat-marketplace
        disabled: true
      - name: redhat-operators
        disabled: true

To install ArgoCD in all-namespaces mode, a subscription is needed that references the argocd-operator from the
community catalog:

argocd-sub.yaml:

    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: argocd-operator
      namespace: openshift-operators
    spec:
      channel: alpha
      installPlanApproval: Automatic
      name: argocd-operator
      source: community-operators
      sourceNamespace: openshift-marketplace
      config:
        env:
        - name: ARGOCD_CLUSTER_CONFIG_NAMESPACES
          value: argocd

Note the environment variable ARGOCD_CLUSTER_CONFIG_NAMESPACES. ArgoCD instances are by default not able to manage
cluster-scoped resources, which is needed for many of the cluster configurations this instance is supposed to configure.
By setting this environment variable to a commaseparated list of the namespaces where ArgoCD instances are deployed,
the instances in those namespaces are allowed to do this. This example deploys ArgoCD in the namespace called "argocd",
so that's what we put as a value.

For ArgoCD to be able to deploy into that namespace, it needs to be created, so lets add a namespace resource:

argocd-ns.yaml:

    apiVersion: v1
    kind: Namespace
    metadata:
      name: argocd
    spec: {}

Now, with the ArgoCD operator installed into the cluster, and the namespace where we want to deploy an instance prepared,
we need to deploy ArgoCD itself. This is done by creating an instance of the argocd CRD resource in the namespace:

argocd.yaml:

    apiVersion: argoproj.io/v1alpha1
    kind: ArgoCD
    metadata:
      finalizers:
      - argoproj.io/finalizer
      name: argocd
      namespace: argocd
    spec:
      resourceCustomizations: |
        bitnami.com/SealedSecret:
          health.lua: |
            hs = {}
            hs.status = "Healthy"
            hs.message = "Controller doesnt report status"
            return hs
        route.openshift.io/Route:
          ignoreDifferences: |
            jsonPointers:
            - /spec/host
      applicationSet:
        resources:
          limits:
            cpu: "2"
            memory: 1Gi
          requests:
            cpu: 250m
            memory: 512Mi
      controller:
        processors: {}
        resources:
          limits:
            cpu: "2"
            memory: 2Gi
          requests:
            cpu: 250m
            memory: 1Gi
        sharding: {}
      grafana:
        enabled: false
        ingress:
          enabled: false
        route:
          enabled: false
      ha:
        enabled: false
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 250m
            memory: 128Mi
      initialSSHKnownHosts:
        excludedefaulthosts: false
        keys: |
          github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==
          github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
          github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
      notifications:
        enabled: false
      prometheus:
        enabled: false
        ingress:
          enabled: false
        route:
          enabled: false
      rbac:
        policy: g, system:cluster-admins, role:admin
      redis:
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 250m
            memory: 128Mi
      repo:
        resources:
          limits:
            cpu: "1"
            memory: 512Mi
          requests:
            cpu: 250m
            memory: 256Mi
      server:
        autoscale:
          enabled: false
        grpc:
          ingress:
            enabled: false
        ingress:
          enabled: false
        resources:
          limits:
            cpu: 500m
            memory: 256Mi
          requests:
            cpu: 125m
            memory: 128Mi
        route:
          enabled: true
        service:
          type: ""
      sso:
        dex:
          openShiftOAuth: true
          resources:
            limits:
              cpu: 500m
              memory: 256Mi
            requests:
              cpu: 250m
              memory: 128Mi
        provider: dex
      tls:
        ca: {}
      kustomizeBuildOptions: "--enable-helm"

This is pretty much a basic argocd deployment, with a few additions:

* The applicationSet section is added, which makes the argocd-operator deploy support for ApplicationSet resources (more on that later).
* Known hosts for the git provider needs to be added, so that ArgoCD trusts them. I use GitHub, so those keys are added. They have been
  collected using the command "ssh-keyscan github.com", and then copied into the initialSSHKnownHosts section as shown above.
* One simple rbac policy has been added, which gives users that are members of the cluster-admins group the ArgoCD role of admin.
* The sso section has been updated to configure Openshift oauth authentication, which makes ArgoCD use Openshift authentication for its
  web interface.
* The kustomizeBuildOptions have been added, with the "--enable-helm" flag. This is needed for ArgoCD to be able to process kustomize
  manifests that use helm.

Finally, the kustomization is added:

kustomization.yaml:

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    
    bases:
    - ../components/repositories
    - ../components/applicationsets
    - ../components/appprojects
    
    resources:
    - argocd-ns.yaml
    - argocd-sub.yaml
    - operatorhub.yaml
    - argocd.yaml
    
    helmCharts:
    - name: sealed-secrets
      repo: https://bitnami-labs.github.io/sealed-secrets
      releaseName: sealedsecrets
      version: 2.6.4
      namespace: kube-system
      valuesInline:
        namespace: kube-system
      includeCRDs: true

The kustomization first defines some bases, which are other directories with kustomizations that will be included when we bootstrap
the cluster. Also, the resources created above are also included.

Lastly, the kustomization will run the SealedSecrets helm chart, fetched from github. Version 2.6.4 is chosen, and the deployment
will be made in the kube-system namespace of the cluster. Also, CRDs are included, so that the cluster will recognize the SealedSecret
resource.

## Creating content in components

The bootstrap kustomization.yaml was configured to include kustomization content from three directories under components -
repositories, applicationsets and appprojects.

### repositories

The repositories directory is intended to include all git repository definitions that ArgoCD uses. At this time, this only includes
the bootstrap repository, but can be expanded with more repositories in the future if needed.

Each repository is represented by a kubernetes Secret, and as it contains sensitive data (the repository credentials), it is created
as a SealedSecret using the following commands:

    oc create secret generic --dry-run=client -n argocd repo-argotest \
      --from-literal=name=argotest \
      --from-literal=project=default \
      --from-file=sshPrivateKey=/home/myuser/.ssh/argocd \
      --from-literal=type=git \
      --from-literal=url="git@github.com:myuser/myrepository" \
      -o yaml | \
      oc label --dry-run=client --local -f /dev/stdin argocd.argoproj.io/secret-type=repository -o yaml | \
      kubeseal --cert=/home/myuser/ss.pem -o yaml > argocd-repo.yaml

This sequence first creates a secret with the keys that ArgoCD expects to see for repository name, AppProject, type and URL. The
content of the private ssh key used to access the git repository is included in the key sshPrivateKey. The output of this command
is piped to the "oc label" command to add the label needed for ArgoCD to recognize the secret as a repository definition. This is
in turn piped to kubeseal, which is the CLI tool from SealedSecret used to create actual encrypted resources. Note that the --cert
flag is used to reference the public key created earlier for SealedSecrets. The resulting output is redirected to the argocd-repo.yaml
file.

The repositories directory is a kustomization base, so it needs a kustomization configuration, which simply includes the repository
files as resources.

kustomization.yaml:

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    
    resources:
    - argocd-repo.yaml

### applicationsets

ArgoCD organizes all the resources it manages into resources called Applications. An Application contains a specification of where
to find the resources, which clusters they should be deployed in (yes ArgoCD can manage multiple clusters), aswell as any
synchronization options.

ApplicationSets are resources that dynamically creates Applications from some type of data source using a specified template for
the Application resource created. These ApplicationSet resources are created in the applicationsets directory.

One ApplicationSet is created in this directory, which will create Applications from git using any subdirectory of the config
directory.

config-applicationset.yaml:

    apiVersion: argoproj.io/v1alpha1
    kind: ApplicationSet
    metadata:
      name: config
      namespace: argocd
    spec:
      generators:
      - git:
          repoURL: git@github.com:myuser/myrepository
          revision: main
          directories:
          - path: config/*
      template:
        metadata:
          name: '{{path.basename}}'
        spec:
          project: default
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
            retry:
              limit: 15
              backoff:
                duration: 15s
                factor: 2
                maxDuration: 5m
          source:
            repoURL: git@github.com:myuser/myrepository
            targetRevision: main
            path: '{{path}}'
          destination:
            server: https://kubernetes.default.svc

The generator configured is the source of the applicationsets, in this case referencing the main branch of the ArgoCD git 
repository, using directories matching path config/* in that repository.

Following the generator, the Application resource template is provided. The name of the resource uses the basename of the
generator path (i.e. the name of the directory matched). The Application is further associated with the default AppProject
(included with ArgoCD deployment, more on AppProjects later), and contains a few synchronization options controlling
pruning, retries etc. The source specifies where the Application can find the resources it manages, and the destination
controls which cluster they should be synchronized to (only the local cluster in this case).

The applicationsets directory is a kustomization base, so it needs a kustomization configuration, which simply includes the
applicationset files as resources.

kustomization.yaml:

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    
    resources:
      - config-applicationset.yaml

### appprojects

As mentioned in the applicationset section, Applications are associated with AppProjects. An AppProject resource is a kind of
policy object, which specifies from WHERE an application is allowed to fetch resources, WHAT resources may be included and
WHERE the resources may be synchronized.

The example ApplicationSet for config/* uses the default AppProject which is created when ArgoCD is deployed. The default
AppProjects contains (unless you modify it) a wildcard specification, meaning it allows resources to be fetched from anywhere,
any resources may be included, and it can be synchronized to any destination configurable.

An ApplicationSet could very well be created for a team of users in your cluster, referencing a git repository owned by the
team, as a way of onboarding the team to the cluster. In such a scenario, it can be benificial to put some controls in by
associating their Applications created by the ApplicationSet to a custom AppProject, which could for example limit them
to only fetch resources from the specified repository, limit the types of resources they could deploy into the cluster,
as well as control which clusters are valid destinations.

An example AppProject is provided below.

team-imaginary.yaml:

    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: team-imaginary
      namespace: argocd
      finalizers:
      - resources-finalizer.argocd.argoproj.io
    spec:
      description: Team Imaginary Project
      sourceRepos:
      - '*'
      destinations:
      - namespace: imaginary-*
        server: https://kubernetes.default.svc

This AppProject allows any source repositories (by wildcard), but limits deployments to the local cluster only, and only
in namespaces whos names starts with the string "imaginary-". See the ArgoCD documentation for more possible options.

The appprojects directory is a kustomization base, so it needs a kustomization configuration, which simply includes the
appproject files as resources.

kustomization.yaml:

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    
    resources:
      - team-imaginary.yaml

## Creating content in config

The config ApplicationSet added earlier is configured to dynamically create Application resources from any subdirectory
of config/. This is where we add cluster configurations to manage with ArgoCD.

For example, to manage one or more groups in the cluster, create a groups/ subdirectory and add group kubernetes resource
files in it:

config/groups/admins.yaml:

    apiVersion: user.openshift.io/v1
    kind: Group
    metadata:
      name: admins
    users:
    - "myuser"

ArgoCD will then monitor the git repository, and make sure this Group resource is configured exactly this way in the cluster.
This means that if the group does not exist, ArgoCD will create it. If it is subsequently deleted, ArgoCD will recreate it.
If the membership list is modified manually by an administrator, ArgoCD will restore it to the definition in git. And, of
course, if the membership list is modified in git, ArgoCD will update the group in the cluster.

A special Application is included in config/selfmanage. This Application only contains a kustomization, which points back
to the bootstrap directory where it all started. This means that once the cluster is bootstrapped, ArgoCD will manage
the whole bootstrap setup as it would any other Application - local changes in the cluster will be reset to the cofiguration
described in git, and changes in these files in git will be synchronized into the cluster. ArgoCD managing ArgoCD!

config/selfmanage/kustomization.yaml:

    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    
    bases:
    - ../../bootstrap/

## Bootstrapping the cluster

Now, with the git repository prepared, and a freshly installed cluster waiting to be configured, we use the kustomize tool
together with oc (Openshift/OKD client) to bootstrap the cluster. To do this, we need the git repository to be updated
in git, as well as a local copy on the filesystem.

First, deploy the SealedSecret keys resource into the cluster:

    oc create -f ss-keys.yaml

Then run kustomize with oc to bootstrap the cluster:

    until kustomize build --enable-helm bootstrap/overlays/default | oc apply -f - ; do sleep 1; done

The bootstrapping is run in a loop which essentially repeats the kustomize build / oc apply command until it returns
without error. This needs to be done because some resources are CRDs, which are not available in the cluster before
the cluster configuration has converged. For example, the ArgoCD CRD is not available until the ArgoCD operator has
completed deployment.

If everything goes well (and it should if the repository contains no errors), after some time ArgoCD should be up and
running in the argocd namespace, SealedSecrets controller should be deployed in the kube-system namespace, the configurations
should be in place and the admins group should have been created.
