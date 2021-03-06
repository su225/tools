#!/bin/bash

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

WD=$(dirname "$0")
WD=$(cd "$WD"; pwd)
ROOT=$(dirname "$WD")

set -eux

# envs for Istio installation
export TAG="${TAG:-}"
export VERSION="${VERSION:-}"
export RELEASE_URL="${RELEASE_URL:-}"
export DNS_DOMAIN="fake-dns.org"
export LOCAL_ISTIO_PATH="${LOCAL_ISTIO_PATH:-}"
export NAMESPACE_NUM="${NAMESPACE_NUM:-15}"
export SKIP_ISTIO_SETUP="${SKIP_ISTIO_SETUP:-false}"

# setup Istio
if [[ ${SKIP_ISTIO_SETUP} != "true" ]];then
# shellcheck disable=SC2199
  if [[ -n "${@}" ]];then
    "${ROOT}"/istio-install/setup_istio.sh "${@}"
  else
    "${ROOT}"/istio-install/setup_istio.sh
  fi
fi

export NOT_INJECTED="True"
# deploy alertmanager related resources
NAMESPACE="istio-prometheus" ./setup_test.sh alertmanager
kubectl apply -f ./alertmanager/prometheusrule.yaml

# deploy log scanner
kubectl create ns logs-checker || true
kubectl create configmap logs-checker --from-file=./logs-checker/check_k8s_logs.sh -n logs-checker || true
./setup_test.sh logs-checker

# This part would be only needed when we run the fully automated jobs on a dedicated cluster
# It would upgrade control plane and data plane to newer dev release every 48h.
# deploy canary upgrader
kubectl create ns canary-upgrader || true
kubectl create configmap canary-script --from-file=./canary-upgrader/canary_upgrade.sh --from-file=./../istio-install/setup_istio.sh -n canary-upgrader || true
./setup_test.sh canary-upgrader

# Setup workloads
pushd "${ROOT}/load"
# shellcheck disable=SC1091
source "./common.sh"
START_NUM=13
export START_NUM="${START_NUM:-0}"
export DELETE=""
export CMD=""
export WD="${ROOT}/load"
if [[ -z ${MULTI_CLUSTER} ]];then
  start_servicegraphs "${NAMESPACE_NUM}" "${START_NUM}"
else
 # run on two cluster
 CTX1=${CTX1} CTX=${CTX2} start_servicegraphs_multicluster "${NAMESPACE_NUM}" "${START_NUM}"
fi
popd