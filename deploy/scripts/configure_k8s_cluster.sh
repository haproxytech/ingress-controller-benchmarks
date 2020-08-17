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

DIRECTORY=~/ingress-controller-benchmarks/
CLUSTER_NAME="k8stmp.k8s.local"
STORE_LOCATION="s3://prefix-k8sbenchmarks-kops-state-store"
CLUSTER_FOUND="false"

display_working() {
    spin='⠇⠏⠋⠉⠙⠹⠸⠼⠴⠤⠦'
    i=0
    pid=$1
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %12 ))
        printf "\r$2 ... ${spin:$i:1}"
        sleep .1
    done
    printf "\r$2 ... \xE2\x9C\x85\n"
}


cd $DIRECTORY

if [ -f "$(which kops)" ]; then
    while [ "$CLUSTER_FOUND" != "true" ]; do
        printf "\rWaiting for cluster to be found ..."
	if [ "$(kops get cluster --state $STORE_LOCATION |grep $CLUSTER_NAME)" ]; then
            CLUSTER_FOUND="true"
            printf " \xE2\x9C\x85\n"
        else
            sleep 1
        fi
    done
    { kops validate cluster --state $STORE_LOCATION --wait 10m --name $CLUSTER_NAME & } >/dev/null 2>&1
    display_working "$!" "Waiting on Kubernetes cluster to be operational"
    #cd ~/k8s-benchmarks/

    if [ -f "$(which kubectl)" ]; then
        configured="false"
        for proxy in haproxy nginx nginx-inc traefik envoy; do
            kubectl get secrets -n app -o name | grep -q "secret/${proxy}$"
            if [ $? -ne 0 ]; then
                configured="false"
                break
            else
                configured="true"
            fi
        done
        if [ "$configured" != "true" ]; then
	    printf "Configuring Kubernetes cluster ...\n"
	    bash deploy/setup.sh
        fi
    else
        printf "\rkubectl missing \xe2\x9d\x8c\n"
        exit 1
    fi
else
    printf "\rkops missing \xe2\x9d\x8c\n"
    exit 1
fi
cat <<EOF
***************************************************
* Configuration complete.                         *
* To execute the benchmarks run the following:    *
*                                                 * 
* For a single node running the traffic injector: *
* ./benchmark.sh single                           *
*                                                 *
* For 5 nodes running the traffic injectors:      *
* ./benchmark.sh saturate                         *
***************************************************

EOF

