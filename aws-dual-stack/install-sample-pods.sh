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
test_ns=dual-stack
$INSTALL_DIR/oc new-project $test_ns

$INSTALL_DIR/oc adm policy add-scc-to-group anyuid "system:serviceaccounts:$test_ns"
$INSTALL_DIR/oc adm policy add-scc-to-group privileged "system:serviceaccounts:$test_ns"
$INSTALL_DIR/kubectl label namespace $test_ns istio-injection=enabled

cat <<EOF | $INSTALL_DIR/oc -n $test_ns apply -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

$INSTALL_DIR/oc apply -f sleep-dual-stack.yaml  -n $test_ns
$INSTALL_DIR/oc apply -f httpbin.yaml -n $test_ns

sleeppod=$($INSTALL_DIR/oc get pods -n $test_ns --no-headers -o custom-columns=":metadata.name" --selector=app=sleep )
$INSTALL_DIR/oc get pods,svc -o wide

$INSTALL_DIR/oc apply -n $test_ns -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: gateway
spec:
  selector:
    istio: ingressgateway # use Istio default gateway implementation
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
EOF

$INSTALL_DIR/kubectl apply -n $test_ns -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: httpbin
spec:
  hosts:
  - "*"
  gateways:
  - gateway
  http:
  - route:
    - destination:
        port:
          number: 8000
        host: httpbin
EOF

echo "*************** MANUAL STEP REQUIRED ***************"
echo "This requires you to manually upgrade the AWS NLB to dualstack https://aws.amazon.com/premiumsupport/knowledge-center/elb-configure-with-ipv6/"


