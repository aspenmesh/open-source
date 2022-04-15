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
OLDIFS=$IFS

usage() {
  cat <<EOF_USAGE
Created by Aspen Mesh:
Add IPv6 underlay networking to an existing ipv4 OpenShift Cluster infrastructure in AWS. Is idempotent and can be
run multiple times.
**Warning: this overwrites and exports KUBECONFIG
Requires: aws cli <2.4.21, openshift (installer, client, pull secret), ssh key, aws route 53 domain
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
export INSTALL_DIR="${workdir}"
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"
echo "KUBECONFIG SET: $KUBECONFIG"
#find the AWS VPC_ID in the openshift terraform state file
if [[ -z "${VPC_ID+x}" ]]; then
  tfstate=$(find "${INSTALL_DIR}" -name "terraform*.tfstate" | head -1)
  echo "Getting VPC_ID from OpenShift terraform statefile: $tfstate"
  if test -f "${tfstate}"; then
   export VPC_ID=$(cat "${tfstate}" | jq -r -s '.[] | first(.resources[] | select(.module =="module.vpc")).instances[0].attributes.vpc_id')
  fi
fi

if [[ -z "${VPC_ID+x}" ]]; then
  echo "VPC_ID required"
  exit 1
fi

echo "Upgrading VPC to dualstack: $VPC_ID"


function getVPCIPV6SubnetBlock(){
  _vpc_id=$1
  VPC_SUBNET_BLOCK=$(aws ec2 describe-vpcs --vpc-id $_vpc_id | jq -e -r '.Vpcs[]  | select( has("Ipv6CidrBlockAssociationSet") == true) | .Ipv6CidrBlockAssociationSet[].Ipv6CidrBlock') && result=true || result=false
  if [[ "$result" == false ]];then
    echo $result
  fi
  echo $VPC_SUBNET_BLOCK
}

################################# VPC
CLUSTER_TAG_NAME=$(aws ec2 describe-vpcs --vpc-id $VPC_ID --query "Vpcs[].Tags[?Key=='Name'][].Value | [0]")

VPC_SUBNET_BLOCK=$(getVPCIPV6SubnetBlock $VPC_ID)
if [[ "$VPC_SUBNET_BLOCK" == false ]]; then
  echo "Attempting to add AWS assigned ipv6 cidr block"
  CIDER_ADDED=$(aws ec2 associate-vpc-cidr-block \
               --amazon-provided-ipv6-cidr-block \
               --ipv6-cidr-block-network-border-group $AWS_DEFAULT_REGION \
               --vpc-id $VPC_ID )
  echo $CIDER_ADDED
  if [[ "$CIDER_ADDED" == *"error"* ]]; then
    echo "unable to assign ipv6 block"
    exit 1
  fi
  VPC_SUBNET_BLOCK=$(getVPCIPV6SubnetBlock $VPC_ID)
  if [[ "$VPC_SUBNET_BLOCK" == false ]]; then
    echo "unable to assign ipv6 block"
    exit 1
  fi
fi

################################# SUBNETS
echo "VPC IPV6 Subnet Block: $VPC_SUBNET_BLOCK"

VPC_SUBNET_ADDRESS=$(echo $VPC_SUBNET_BLOCK | sed 's/\/56//')
echo "Using VPC subnet address block $VPC_SUBNET_ADDRESS"

#generate 16 subnets from the VPC ipv6 block of size /64  4 bits between 60 to 64
IFS=$'\n' IPV6SUBNETS=($(sipcalc -S 64 $VPC_SUBNET_ADDRESS/60  -u | grep "Expanded Address" | awk '{print $4}'))
echo "Generated ${#IPV6SUBNETS[@]} subnets"

AWS_SUBNET_DESC=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" )

echo $AWS_SUBNET_DESC | jq -r '.Subnets[] | select(.Ipv6CidrBlockAssociationSet[].Ipv6CidrBlockState.State=="associated") | .SubnetId'

IFS=$'\n' AWS_SUBNETS=($(echo $AWS_SUBNET_DESC | jq -r '.Subnets[].SubnetId'))
echo "Found subnets in VPC: ${AWS_SUBNETS[@]}"
echo "---------------------------"
num_ipv6_subnets=${#IPV6SUBNETS[@]}
num_aws_subnets=${#AWS_SUBNETS[@]}

if [[ "$num_ipv6_subnets" -le "$num_aws_subnets" ]]; then
  echo "Test failed: This script assumed Openshift created ${num_aws_subnets} subnets by default"
  echo "Not enough subnets: $num_ipv6_subnets <= $num_aws_subnets"
  exit 1
fi

for (( j=0; j<${num_aws_subnets}; j++ ));
do
  SUBNET_ID="${AWS_SUBNETS[$j]}"

  AWS_SUBNETS_W_IPV6=$(echo $AWS_SUBNET_DESC | jq -r '.Subnets[] | select(.Ipv6CidrBlockAssociationSet[].Ipv6CidrBlockState.State=="associated") | .SubnetId' | grep "$SUBNET_ID" || true)

  if [[ -z "$AWS_SUBNETS_W_IPV6" ]]; then
    printf "Adding ipv6 block: %s to %s\n"  "${IPV6SUBNETS[$j]}/64" "$SUBNET_ID"
    subnet_applied=$(aws ec2 associate-subnet-cidr-block --subnet-id $SUBNET_ID --ipv6-cidr-block "${IPV6SUBNETS[$j]}/64")
    echo $subnet_applied
  else
    echo "Skipping SubnetID: $AWS_SUBNETS_W_IPV6"
  fi

done

echo "---------------------------"
################################# route-tables public
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Tags[?Key==`Name` && contains(Value,`public`)]]' )
ROUTE_TABLE_ID=$(echo $ROUTE_TABLES | jq -r '.[].RouteTableId')
if [ -z "$ROUTE_TABLE_ID" ];then
  echo "Public ROUTE_TABLE not found"
  exit 1
fi

INTERNET_GATEWAYID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" | jq -r '.InternetGateways[].InternetGatewayId')
if [ -z "$INTERNET_GATEWAYID" ];then
  echo "Public INTERNET_GATEWAYID not found"
  exit 1
fi

ROUTE_TABLE_CHECK=$(echo $ROUTE_TABLES | grep "$INTERNET_GATEWAYID" | wc -l)
if [[ "$ROUTE_TABLE_CHECK" == 0 ]]; then
  echo "ADDING public route"
  ADDED_ROUTE=$(aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-ipv6-cidr-block ::/0 --gateway-id $INTERNET_GATEWAYID)
  echo "ADDED_ROUTE $ADDED_ROUTE"
else
  echo "Skipping public route table"
fi

echo "---------------------------"
#################################  route-tables private Egress-gateway

IFS=$'\n' EGRESS_GATEWAY_ID=$(aws ec2 describe-egress-only-internet-gateways --query "EgressOnlyInternetGateways[?Attachments[?VpcId=='$VPC_ID']]" | jq -r '.[].EgressOnlyInternetGatewayId')

if [ -z "$EGRESS_GATEWAY_ID" ];then
  EGRESS_GATEWAY_ID=$(aws ec2 create-egress-only-internet-gateway --vpc-id $VPC_ID --tag-specifications "ResourceType=egress-only-internet-gateway,Tags=[{Key=Name,Value=$CLUSTER_TAG_NAME}]" | jq -r '.EgressOnlyInternetGateway.EgressOnlyInternetGatewayId')
fi

echo "EGRESS_GATEWAY_ID: $EGRESS_GATEWAY_ID"

IFS=$'\n' ROUTE_TABLES=($(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Tags[?Key==`Name` && contains(Value,`private`)]]' | jq -r '.[].RouteTableId'))
echo "ROUTE_TABLES $ROUTE_TABLES"

if [ -z "$ROUTE_TABLES" ];then
  echo "Private ROUTE_TABLES not found"
  exit 1
fi

for PRIVATE_ROUTE_TABLE in "${ROUTE_TABLES[@]}"
do
  echo "This is Idempotent: create route for private route $PRIVATE_ROUTE_TABLE to egress gateway $EGRESS_GATEWAY_ID"
  ADDED_ROUTE=$(aws ec2 create-route --route-table-id $PRIVATE_ROUTE_TABLE --destination-ipv6-cidr-block ::/0 --egress-only-internet-gateway-id $EGRESS_GATEWAY_ID)
  echo $ADDED_ROUTE
done

echo "---------------------------"
#################################  security group rules

IFS=$'\n' SECURITY_GROUPS_HAVE_IPV6=($(aws ec2 describe-security-groups \
                                 --filters Name=vpc-id,Values=$VPC_ID  \
                                 --query "SecurityGroups[?IpPermissions[?Ipv6Ranges[?contains(Description,'ipv6-am')]]].{Name:GroupName,ID:GroupId}" | jq -r '.[] | select(.Name | startswith("terraform")) | .ID'))

if [[ "${#SECURITY_GROUPS_HAVE_IPV6[@]}" == 0 ]];then
  echo "SECURITY_GROUPS_HAVE_IPV6 not found; assuming ipv6 is needed"
  IFS=$'\n' SECURITY_GROUPS=($(aws ec2 describe-security-groups \
                                   --filters Name=vpc-id,Values=$VPC_ID  \
                                   --query 'SecurityGroups[*].{Name:GroupName,ID:GroupId}' | jq -r '.[] | select(.Name | startswith("terraform")) | .ID'))

  if [ "$#SECURITY_GROUPS[@]" == 0 ];then
    echo "SECURITY_GROUPS not found"
    exit 1
  fi
  for GROUP_ID in "${SECURITY_GROUPS[@]}"
  do
    echo "Attempting to add ipv6 rules to SecurityGroup: $GROUP_ID"
    SECURITY_GROUP_ADDED=$(aws ec2 authorize-security-group-ingress \
        --group-id $GROUP_ID \
        --ip-permissions \
        IpProtocol=tcp,FromPort=22,ToPort=22,Ipv6Ranges='[{CidrIpv6=::/0,Description="ssh-ipv6"}]' \
        IpProtocol=icmpv6,FromPort=-1,ToPort=-1,Ipv6Ranges='[{CidrIpv6=::/0,Description="icmp-ipv6"}]' \
        IpProtocol=-1,FromPort=-1,ToPort=-1,Ipv6Ranges='[{CidrIpv6=::/0,Description="all-ipv6"}]')
    echo $SECURITY_GROUP_ADDED
  done
else
  echo "Skipping Security Groups"
fi

echo "---------------------------"
################################# EC2
#add an ipv6 address to all EC2 instances in the vpc that dont have one
IFS=$'\n' ENI_IDS=($(aws ec2 describe-instances \
                       --filters Name=vpc-id,Values=$VPC_ID  \
                       --query 'Reservations[?Instances[?NetworkInterfaces[?length(Ipv6Addresses)==`0`]]]' | \
                       jq -r '.[].Instances[].NetworkInterfaces[].NetworkInterfaceId'))

if [[ "${#ENI_IDS[@]}" -gt 0 ]];then
  for eni_id in "${ENI_IDS[@]}"
  do
    echo "Attempting to assign ipv6 address to EC2 ENI: $eni_id"
    ENI_ASSIGNED=$(aws ec2 assign-ipv6-addresses --network-interface-id $eni_id --ipv6-address-count 1)
  done
else
  echo "Skipping EC2"
fi

echo "---------------------------"
################################# LoadBalancer

#find LB with name like '*ext*' == external == public requires a type change
LB_ARN=($(aws elbv2 describe-load-balancers  \
          --query "LoadBalancers[?VpcId=='$VPC_ID' && contains(LoadBalancerArn,'ext') && IpAddressType != 'dualstack'].LoadBalancerArn" | \
          jq -r '.[]'))

if [[ "${#LB_ARN[@]}" == 1 ]];then
  echo "LoadBalancer ARN found $LB_ARN"
  LB_CONVERTED=$(aws elbv2 set-ip-address-type --load-balancer-arn $LB_ARN --ip-address-type dualstack)
  echo $LB_CONVERTED
else
  echo "Skipping LoadBalancer"
fi

IFS=$OLDIFS
