#!/bin/bash
set -Eueo pipefail

usage() {
  cat <<EOF_USAGE
Created by Aspen Mesh:
This script adds IPv6 overlay networking to an existing ipv4 OpenShift Cluster in AWS. Waits for all OpenShift Network pods
to be upgraded before completion.
Requires: kubectl, openshift (cluster, installer, client, pull secret), aws cli and creds
Tested on OSX 11.6

Usage: ${scriptName} <cluster_name>
Arguments:
                cluster_name: [string]
EOF_USAGE
  exit 1
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi


cluster=$1
workdir=_install_

## Global vars
INSTALL_DIR="${workdir}"
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
export OC_CMD="$INSTALL_DIR/oc"
export KC_CMD="$INSTALL_DIR/kubectl"

mkdir -p "${INSTALL_DIR}"

THIS_SCRIPT_DIR="$(cd $(dirname ${BASH_SOURCE}); pwd)"

#must match ipv6 cider in oc-dualstack-add.yaml
IPV6_CIDR="fd00:abcd:102::/48"
function check_ipv6(){
  has_ipv6=false
  has_ipv6=$($OC_CMD get network -o json | jq -r '.items[].spec.clusterNetwork[].cidr' | grep "$IPV6_CIDR" || true)
  echo $has_ipv6
}

IPV6_ENABLED=$(check_ipv6)
echo "IPV6_ENABLED: $IPV6_ENABLED"
if [ "$IPV6_ENABLED" != "$IPV6_CIDR" ]; then
  echo "Applying ipv6 network changes"
  (
    cp "${THIS_SCRIPT_DIR}/oc-dualstack-add.yaml" "${INSTALL_DIR}/oc-dualstack-add.yaml"
#    cd "${INSTALL_DIR}"
    $OC_CMD patch network.config.openshift.io cluster --type='json' --patch-file oc-dualstack-add.yaml
    sleep 5
    # Openshift rolls out changes to the pods in ns openshift-ovn-kubernetes
    # waiting on these network updates to ensure network is ready for traffic before continuing
    $OC_CMD wait --for=condition=progressing=false clusteroperators/network --timeout=10m
  )
fi

IPV6_ENABLED=$(check_ipv6)
if [ "$IPV6_ENABLED" != "$IPV6_CIDR" ]; then
  echo "FAILED setting up IPV6:$IPV6_ENABLED"
  exit 1
else
  echo "Dual Stack configured properly"
fi
