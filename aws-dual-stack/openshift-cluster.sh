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


set -euEo pipefail
scriptName=$(basename "$0")
workdir=_install_
##################### EDIT PARAMETERS ###########################

installer_tar="openshift-install-mac.tar.gz"
client_tar="openshift-client-mac.tar.gz"
base_domain="DOMAIN_NAME_IN_ROUTE_53"
ssh_pub_key=$(cat $workdir/openshift-test-ssh.pub)
pull_secret=$(cat $workdir/pull-secret.txt)

##################################################################

usage() {
  cat <<EOF_USAGE
Created by Aspen Mesh:
This script is intended to create or delete an openshift 4.x cluster on aws
Requires: yq 3.4.1, aws cli <2.4.21, openshift (installer, client, pull secret), ssh key, aws route 53 domain
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

cluster_name=$1

cp template.install-config.yaml $workdir/install-config.yaml
cd $workdir

function validate_reqs(){
  reqs=("aws" "yq" "tar")
  for i in $reqs; do
    if ! command -v $i &> /dev/null
    then
        echo "$i could not be found"
        exit 1
    fi
  done
}

function prep_cluster(){

  # extract tar files
  tar -xf  "${installer_tar}"
  tar -xf  "${client_tar}"

  yq w -i -- install-config.yaml 'baseDomain' "${base_domain}" || {
   echo "Error: failed to set metadata.name"
   exit 1
  }

  yq w -i -- install-config.yaml 'metadata.name' "${cluster_name}" || {
   echo "Error: failed to set metadata.name"
   exit 1
  }

  yq w -i -- install-config.yaml 'sshKey' "${ssh_pub_key}" || {
   echo "Error: failed to set sshKey"
   exit 1
  }

  yq w -i -- install-config.yaml 'pullSecret' "${pull_secret}" || {
   echo "Error: failed to set pullSecret"
   exit 1
  }

  if [[ ! -z ${AWS_DEFAULT_REGION:-} ]]; then
     yq w -i -- install-config.yaml 'platform.aws.region' "${AWS_DEFAULT_REGION}" || {
       echo "Error: failed to set AWS Default Region"
       exit 1
     }
  fi
}

validate_reqs
echo "Info: start creating OpenShift cluster: name=$cluster_name, workdir=$workdir ..."
prep_cluster
./openshift-install create cluster --dir=. --log-level=debug || {
 echo "Error: failed to create cluster: ${cluster_name}"
 return 1
}

echo "Info: cluster ${cluster_name} is sucessfully created"



