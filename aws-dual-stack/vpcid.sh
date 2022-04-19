#!/bin/bash

function vercomp () {
    if [[ $1 == "$2" ]]
    then
        echo 0
        return
    fi
    local IFS=.
    # shellcheck disable=2206
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            echo 1
            return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            echo 2
            return
        fi
    done
    echo 0
    return 0
}

function getVPCID() {
  ocp_version=$(oc version -o json  | jq '.openshiftVersion' | sed 's/\"//g')
  comp=$(vercomp 4.9.0 "${ocp_version}")

  if [[ ${comp} == 1 ]]
  then
      tfstate=$(find "${INSTALL_DIR}" -name "terraform*.tfstate" | head -1)
  else
      tfstate=$(find "${INSTALL_DIR}" -name "terraform.cluster.tfstate" | head -1)
  fi
  if test -f "${tfstate}"; then
    VPC_ID=$(cat "${tfstate}" | jq -r -s '.[] | first(.resources[] | select(.module =="module.vpc")).instances[0].attributes.vpc_id')
    echo ${VPC_ID}
    return
  fi

  echo "VPC_ID required"
  return 1
}
