#!/bin/bash
# Copyright 2020 HAProxy Technologies LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CLUSTER_NAME=$(kubectl config current-context)

if [ -z "$CLUSTER_NAME" ]; then
    echo -e "Kubectl failed to access a Kubernetes cluster \xe2\x9d\x8c" 
    exit 1
fi

# Configure controller dedicated node
#####################################

C_NODE=$(kubectl get nodes |grep -v master | grep Ready | cut -d' ' -f1 | head -1 )

if [ -z "$C_NODE" ]; then
    echo -e "Unable to find a Ready to deploy ingress controllers ... \xe2\x9d\x8c"
    exit 1
fi

kops get cluster k8stmp.k8s.local --state=s3://prefix-k8sbenchmarks-kops-state-store -o yaml|awk '{print} /type: Public/ && !n {print "      idleTimeoutSeconds: 900"; n++}' > cluster.yaml 
kops replace --state=s3://prefix-k8sbenchmarks-kops-state-store -f cluster.yaml >/dev/null 2>&1 
kops update cluster --state=s3://prefix-k8sbenchmarks-kops-state-store k8stmp.k8s.local --yes >/dev/null 2>&1

echo -n "Set \"$C_NODE\" as dedicated node for ingress controllers ... "
kubectl taint --overwrite nodes $C_NODE dedicated=controller:NoSchedule >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "\xe2\x9d\x8c [Taint setup failed on \"$C_NODE\"]"
    exit 1
else
    echo -e "\xE2\x9C\x85"
fi

echo -n "Setting labels on \"$C_NODE\"  ... "
kubectl label --overwrite nodes $C_NODE dedicated=controller >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "\xe2\x9d\x8c [Label setup failed on \"$C_NODE\"]"
else
    echo -e "\xE2\x9C\x85"
fi


# Installing Ingress Controllers
################################
echo -n "Adding Helm repositories ... "
helm repo add haproxytech https://haproxytech.github.io/helm-charts >/dev/null 2>&1
helm repo add nginx-stable https://helm.nginx.com/stable >/dev/null 2>&1
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1
helm repo add traefik https://containous.github.io/traefik-helm-chart >/dev/null 2>&1
helm repo update >/dev/null 2>&1
echo -e "\xE2\x9C\x85"

declare -A HELM
HELM[haproxy]=haproxytech/kubernetes-ingress
HELM[nginx]=ingress-nginx/ingress-nginx
HELM[nginx-inc]=nginx-stable/nginx-ingress
HELM[traefik]=traefik/traefik

echo "Installing ingress controllers ..."
for C in "${!HELM[@]}"; do 
    helm ls | grep -q "$C\s"
    if [ $? -ne 0 ]; then
        helm install $C -f deploy/helm/$C.yml ${HELM[$C]}> /dev/null
        if [ $? -ne 0 ]; then
            echo -e "\t \xe2\x9d\x8c [Install of $C controller failed]"
            exit 1
        else
            echo -e "\t \xE2\x9C\x85 $C controller installed"
        fi
    else
        echo -e "\t \xE2\x9C\x85 $C controller already installed"
    fi
done

kubectl apply -f deploy/manifests/contour.yml > /dev/null
if [ $? -eq 0 ]; then
    echo -e "\t \xE2\x9C\x85 contour/envoy controller installed"
else
    echo "\t \xe2\x9d\x8c [Install of contour controller failed]"
    exit 1
fi

# Update NginxInc service
kubectl get service nginx-inc-nginx-ingress > /dev/null 2>&1
if [ $? -eq 0 ]; then
    kubectl get service nginx-inc-nginx-ingress -o yaml | sed  's/clusterIP:.*/clusterIP: None/' | kubectl replace --force -f - >/dev/null 2>&1
    kubectl get service nginx-inc-nginx-ingress -o yaml | sed  's/name: nginx-inc-nginx-ingress/name: nginx-inc/' | kubectl apply -f - >/dev/null 2>&1
    kubectl delete service nginx-inc-nginx-ingress >/dev/null 2>&1
fi


# Install echo application
##########################

# Helm
kubectl create ns app >/dev/null 2>&1
git clone https://github.com/Mo3m3n/http-echo-chart.git /tmp/http-echo-chart >/dev/null 2>&1

helm ls -n app| grep -q "echo\s"

if [ $? -ne 0 ]; then
    echo -n "Installing echo app ... "
    helm install echo -n app /tmp/http-echo-chart --set fullnameOverride=echo --set replicaCount=10 --set ingress.enabled=false >/dev/null 2>&1
    echo -e "\xE2\x9C\x85"
fi

rm -rf /tmp/http-echo-chart >/dev/null 2>&1

echo "Applying CRDs ..."
# Install HTTPProxy CRD
kubectl -n app apply -f deploy/manifests/crd/envoy/httpproxy.yaml >/dev/null 2>&1
echo -e "\t \xE2\x9C\x85 contour/envoy CRDs applied"
# Install IngressRoute CRD
kubectl -n app apply -f deploy/manifests/crd/traefik/traefik.ingressroute.yaml >/dev/null 2>&1
kubectl -n app apply -f deploy/manifests/crd/traefik/traefiktls.ingressroute.yaml >/dev/null 2>&1
kubectl -n app apply -f deploy/manifests/crd/traefik/replace-path.middleware.yaml >/dev/null 2>&1
kubectl -n app apply -f deploy/manifests/crd/traefik/addcors.middleware.yaml >/dev/null 2>&1
echo -e "\t \xE2\x9C\x85 traefik CRDs applied"

sleep 30

# Install Ingress rules
echo "Applying Ingress rules ..."

for i in deploy/manifests/ingress/*; do
    ingress=${i##*/}
    kubectl apply -f  $i >/dev/null 2>&1
    echo -e "\t \xE2\x9C\x85 ${ingress%%.*}"
done


# Create default certificates
echo "Adding Secrets ..."	
for proxy in haproxy nginx nginx-inc traefik envoy; do
    kubectl get secrets -n app -o name | grep -q "secret/${proxy}$"
    if [ $? -ne 0 ]; then
        ./deploy/scripts/create-default-cert.sh $proxy >/dev/null 2>&1
	echo -e "\t \xE2\x9C\x85 $proxy"
    fi
done

# Update Nginx service name from "nginx-controller" to "nginx"
kubectl get service nginx-controller > /dev/null 2>&1
if [ $? -eq 0 ]; then
    kubectl get service nginx-controller -o yaml | sed  's/name: nginx-controller/name: nginx/' | kubectl apply -f - >/dev/null 2>&1
    kubectl delete service nginx-controller >/dev/null 2>&1
fi

kubectl  patch deployment nginx-inc --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/securityContext/runAsUser", "value":0}]'  >/dev/null 2>&1
kubectl  patch deployment nginx-inc --type='json' -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/securityContext/capabilities", "value":[]}]'  >/dev/null 2>&1

