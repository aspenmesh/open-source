# How to create a new dual-stack cluster in aws

### Prepare for installation
Download openshift installer to the _install_ directory
https://developers.redhat.com/products/openshift/download
- "Install Red Hat OpenShift on your laptop"
- click "Downloads" on left menu 
- Download "OpenShift command-line interface (oc)"
- Download "OpenShift for x86_64 Installer"
- Scroll to bottom "Tokens" Download Pull Secret _install_/pull-secret.txt

Create a new ssh key in the _install_ directory
`ssh-keygen -t rsa -f _install_/openshift-test-ssh`

Edit params at the top of `./openshift-cluster.sh`

### Create the AWS OpenShift Cluster

```bash
./openshift-cluster.sh test-openshift-5
```
This shell script will create a full working OpenShift 4.x cluster in AWS. Successful run will output 'INFO Install complete!'
along with the username and password for the web console. Takes aprox 30-45m

Requires: yq 3.4.1, aws cli <2.4.21, openshift (installer, client, pull secret), ssh key, aws route 53 domain

### Upgrade AWS networking

```bash
./openshift-upgrade-aws.sh test-openshift-5
```
Script upgrades the AWS underlay networking infrastructure on an existing ipv4 OpenShift Cluster in AWS to add ipv6 capability
We chose an upgrade path because the OpenShift installer does not yet have the ability to enable dual stack for AWS.

[AWS dual stack networking instructions](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-migrate-ipv6.html#vpc-migrate-assign-ipv6-address)

**Known issues:**
1. Adding a new Istio ingress gateway by default uses an AWS classic Load Balancer. The LB has be overridden to use an NLB
instead of a classic. The next problem is that the annotation for setting the AWS NLB to dualstack is currently unsupported 
in the latest OpenShift 4.10 controller. This means that even with this NLB setting you will need to manually change the LB from 
`ipv4` to `dualstack`
```istio
gateways:
  istio-ingressgateway:
    serviceAnnotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      #unsupported
      #service.beta.kubernetes.io/aws-load-balancer-ip-address-type: "dualstack"
      #alb.ingress.kubernetes.io/ip-address-type: "dualstack"
```
2. AWS NLB dualstack relies on ipv4 network translation so AWS still doesn't have full E2E ipv6/dualstack support

### Upgrade OpenShift internal networking
```bash
./openshift-upgrade-cluster.sh test-openshift-5
```
Running the upgrade-cluster adds dual stack networking to the openshift cluster internals and will allow traffic to 
use dualstack capabilities.

### Delete OpenShift internal networking
```bash
./openshift-cluster-delete.sh
```
Removes added AWS infrastructure prior to running the OpenShift Delete
uses the metadata.json from the cluster creation to delete the existing cluster



