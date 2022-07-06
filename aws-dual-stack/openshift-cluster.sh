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

base_domain="dev.twistio.io"
ssh_pub_key=$(cat $workdir/id_rsa.pub)
pull_secret=$(echo $PULL_SECRET_B64 | base64 -d)

##################################################################

usage() {
  cat <<EOF_USAGE
Created by Aspen Mesh:
This script is intended to create or delete an openshift 4.x cluster on aws
Requires: yq 3.4.1, aws cli <2.4.21, openshift (installer, client, pull secret), ssh key, aws route 53 domain
Tested on OSX 11.6

Usage: ${scriptName}
ENV:
                CLUSTER_NAME: [string]
EOF_USAGE
  exit 1
}

cluster_name=$CLUSTER_NAME

cp template.install-config.yaml $workdir/install-config.yaml
cd $workdir

##shim yq 3.4 cant be installed easily in osx
#yq() {
#    docker run --rm -i -v ${PWD}:/workdir mikefarah/yq:3.4.1 yq "$@"
#}


function prep_cluster(){

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

echo "Info: start creating OpenShift cluster: name=$cluster_name, workdir=$workdir ..."
prep_cluster
./openshift-install create cluster --dir=. --log-level=debug || {
 echo "Error: failed to create cluster: ${cluster_name}"
}

echo "Info: cluster ${cluster_name} is sucessfully created"



