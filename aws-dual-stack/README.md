# How to create a new dual-stack cluster in aws

Scripts here have been designed and tested on OpenShift 4.x and may not work on future versions.

These are just samples scripts. DO NOT USE IN PRODUCTION!

Istio requires fairly large instances to run properly on top of OpenShift `5x m5.2xlarge` is set by default in the install-config. Please be aware that running these scripts may incur costs in your AWS account!

Pull Requests are welcome, we have tested these scripts on OSX.

[See accompanying presentation slides](https://github.com/aspenmesh/open-source/blob/main/istiocon2022/Dual-Stack-Josht-istiocon22.pptx) 

**Requirements:**
- yq 3.4.1, aws cli <2.4.21, openshift (installer, client, pull secret), ssh key, aws route 53 domain
- AWS environment variables

### Prepare for installation

```bash
make -p _install_
```
_install_ is purposefully in the gitignore so secrets are not leaked.

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
./openshift-cluster.sh test-openshift
```
This shell script will create a full working OpenShift 4.x cluster in AWS. Successful run will output 'INFO Install complete!'
along with the username and password for the web console. Takes aprox 30-45m

[OpenShift AWS install instructions](https://docs.openshift.com/container-platform/4.8/installing/installing_aws/installing-aws-default.html)

### Upgrade AWS networking

```bash
./openshift-upgrade-aws.sh test-openshift
```
Script upgrades the AWS underlay networking infrastructure on an existing ipv4 OpenShift Cluster in AWS to add ipv6 capability
We chose an upgrade path because the OpenShift installer does not yet have the ability to enable dual stack for AWS. [See installer code](https://github.com/openshift/installer/blob/0da415500bd87009c5903705048712e17e3051ad/pkg/types/validation/installconfig.go#L254)

[AWS dual stack networking instructions](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-migrate-ipv6.html#vpc-migrate-assign-ipv6-address)

**Known issues:**
1. Adding a new Istio ingress gateway by default uses an AWS classic Load Balancer. The LB has be overridden to use an NLB
instead of a classic. 
2. The next problem is that the annotation for setting the AWS NLB to dualstack is currently unsupported 
in the latest OpenShift 4.10 controller. This means that even with this NLB setting you will need to manually change the LB from 
`ipv4` to `dualstack`
```istio
gateways:
  istio-ingressgateway:
    serviceAnnotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      #These annotations are unsupported in the OpenShift Controller
      #service.beta.kubernetes.io/aws-load-balancer-ip-address-type: "dualstack"
      #alb.ingress.kubernetes.io/ip-address-type: "dualstack"
```
2. AWS NLB dualstack relies on ipv4 network translation so AWS still doesn't have full E2E ipv6/dualstack support

### Upgrade OpenShift internal networking

```bash
./openshift-upgrade-cluster.sh test-openshift
```
Running the upgrade-cluster adds dual stack networking to the openshift cluster internals and will allow traffic to 
use dualstack capabilities.

### Install AspenMesh ( DualStack features have not yet been released into opensource Istio )

- Sign up for an account https://aspenmesh.io/invite/
- Visit https://my.aspenmesh.io/
- Follow the documentation
  - Install 1.11.8-am2 **(Istio + Dual Stack features)** sample [overrides](overrides.yaml) for OpenShift

### Setup Test Pods and data

```bash
./install-sample-pods.sh
```
Creates namespace dual-stack and sets up privileges and a sleep and httpbin pod with Istio sidecars. It also creates a VirtualService and IngressGateway to validate we can reach the cluster publicly.
**[This requires you to manually upgrade the AWS NLB to dualstack](https://aws.amazon.com/premiumsupport/knowledge-center/elb-configure-with-ipv6/)**


```bash
sleeppod=$(_install_/oc get pods -n dual-stack --no-headers -o custom-columns=":metadata.name" --selector=app=sleep )
_install_/oc exec -n dual-stack -it $sleeppod sh

_install_/oc exec -n dual-stack -it $sleeppod -- curl -I -6 httpbin:8000
_install_/oc exec -n dual-stack -it $sleeppod -- curl -I -4 httpbin:8000
_install_/oc exec -n dual-stack -it $sleeppod -- nslookup httpbin.dual-stack.svc.cluster.local
_install_/oc exec -n dual-stack -it $sleeppod -- nslookup -type=aaaa httpbin.dual-stack.svc.cluster.local
```
Validate traffic between pods is working


```bash
./test-dual-stack.sh
```
Validate external traffic is working

### Delete OpenShift Cluster

```bash
./openshift-delete-cluster.sh
```
Removes added AWS infrastructure prior to running the OpenShift Delete
uses the metadata.json from the cluster creation to delete the existing cluster



