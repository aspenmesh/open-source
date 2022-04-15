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

workdir=_install_
export INSTALL_DIR="${workdir}"
export KUBECONFIG="${INSTALL_DIR}/auth/kubeconfig"

$INSTALL_DIR/oc get clusterversion
$INSTALL_DIR/oc get network -o json | jq '.items[].status'

INGRESS_PORT=$($INSTALL_DIR/kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
INGRESS_HOST=$($INSTALL_DIR/kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST:$INGRESS_PORT/status/200"
curl -6 -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST:$INGRESS_PORT/status/200"

