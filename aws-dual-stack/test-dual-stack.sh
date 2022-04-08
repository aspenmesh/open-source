#!/bin/bash


export TEST_NS=dual-stack
oc new-project $TEST_NS

oc adm policy add-scc-to-group anyuid "system:serviceaccounts:$TEST_NS"
oc adm policy add-scc-to-group privileged "system:serviceaccounts:$TEST_NS"
kubectl label namespace $TEST_NS istio-injection=enabled

cat <<EOF | oc -n $TEST_NS create -f -
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: istio-cni
EOF

oc apply -f sleep-dual-stack.yaml  -n $TEST_NS
oc apply -f httpbin.yaml -n $TEST_NS

sleeppod=$(oc get pods --no-headers -o custom-columns=":metadata.name" --selector=app=sleep )
oc get pods,svc -o wide

kubectl apply -f - <<EOF
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

kubectl apply -f - <<EOF
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

export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "******************************"

curl -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST:$INGRESS_PORT/status/200"
curl -6 -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST:$INGRESS_PORT/status/200"

echo "******************************"
exit 1

oc get pods,svc -o wide
sleeppod=$(oc get pods --no-headers -o custom-columns=":metadata.name" --selector=app=sleep )
oc exec -it $sleeppod sh

echo "******************************"

curl -I -6 httpbin:8000
curl -I -4 httpbin:8000

echo "******************************"

nslookup httpbin.$TEST_NS.svc.cluster.local
nslookup -type=aaaa httpbin.$TEST_NS.svc.cluster.local

echo "******************************"

oc get pods,svc -o wide
oc get clusterversion
#oc get pods simpleserver-694c98c44c-4ps4x -o json | jq '.metadata.annotations."k8s.ovn.org/pod-networks"'
oc get network -o json | jq '.items[].status'

curl httpbin:8000/get

