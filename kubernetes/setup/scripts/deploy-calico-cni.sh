#!/usr/bin/env bash

set -euxo pipefail

source "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/_variables.sh"

function deploy_calico_cni() {
  manifest=()
  for _file in $(ls -1 ${ADDON_DIR}/calico/*.yaml)
  do
    manifest+=("-f" "${_file}")
  done

  kubectl apply \
    --kubeconfig ${CONFIG_DIR}/admin.kubeconfig \
    -n kube-system \
    "${manifest[@]}"

}

deploy_calico_cni