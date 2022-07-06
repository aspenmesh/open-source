#!/bin/bash
# Portions Copyright Aspen Mesh Authors.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#    http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

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

scriptdir=$(dirname "$0")
source "${scriptdir}/vpcid.sh"
VPC_ID=$(getVPCID)

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
