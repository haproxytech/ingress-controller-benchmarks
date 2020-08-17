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

openssl rand -out ~/.rnd -writerand ~/.rnd

for p in "$@"; do
    HOST=$p.default
    KEY_FILE=$p.key
    CERT_FILE=$p.crt
    CERT_NAME=$p
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/${KEY_FILE} -out /tmp/${CERT_FILE} -subj "/CN=${HOST}/O=Controller"
    kubectl create secret tls -n app ${CERT_NAME} --key /tmp/${KEY_FILE} --cert /tmp/${CERT_FILE}
    rm -f  /tmp/${KEY_FILE} /tmp/${CERT_FILE}
done

