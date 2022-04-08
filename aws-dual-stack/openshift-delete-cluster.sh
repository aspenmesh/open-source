#!/bin/bash
set -Eueo pipefail
scriptName=$(basename "$0")

usage() {
  cat <<EOF_USAGE
Created by Aspen Mesh:
Delete any dual stack resources that block the openshift cli, uses the metadata.json so no parameters are needed
Requires: openshift (cluster, installer, client, pull secret), aws cli and creds
Tested on OSX 11.6

Usage: ${scriptName}
EOF_USAGE
  exit 1
}

## Global vars
INSTALL_DIR="_install_"
export KUBECONFIG="$INSTALL_DIR/auth/kubeconfig"
export OC_INSTALL_CMD="$INSTALL_DIR/openshift-install"
export KC_CMD="$INSTALL_DIR/kubectl"

#find the AWS VPC_ID so resources in the VPC can be destroyed
if [[ -z "${VPC_ID+x}" ]]; then
  tfstate=$(find "${INSTALL_DIR}" -name "terraform*.tfstate" | head -1)
  echo $tfstate
  if test -f "${tfstate}"; then
   export VPC_ID=$(cat "${tfstate}" | jq -r -s '.[] | first(.resources[] | select(.module =="module.vpc")).instances[0].attributes.vpc_id')
  fi
fi

if [[ -z "${VPC_ID+x}" ]]; then
  echo "VPC_ID required"
  exit 1
fi

EGRESS_GATEWAY_ID=$(aws ec2 describe-egress-only-internet-gateways --query "EgressOnlyInternetGateways[?Attachments[?VpcId=='$VPC_ID']]" | jq -r '.[].EgressOnlyInternetGatewayId')
if [ ! -z "$EGRESS_GATEWAY_ID" ];then
  output=$(aws ec2 delete-egress-only-internet-gateway --egress-only-internet-gateway-id $EGRESS_GATEWAY_ID | jq -r '.ReturnCode')
  #Do we want to send a notification to slack on failure? Retry??
  echo "Deleted AWS EGRESS_GATEWAY_ID:$EGRESS_GATEWAY_ID - $output"
fi

echo $OC_INSTALL_CMD

$OC_INSTALL_CMD destroy cluster --dir=$INSTALL_DIR --log-level=info || {
   echo "Warning: delete cluster with error return code: $?"
   return 1
}
