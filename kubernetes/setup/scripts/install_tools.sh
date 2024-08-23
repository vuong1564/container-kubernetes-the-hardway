#!/usr/bin/env bash

set -euxo pipefail

source "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/_variables.sh"

function install_cfssl() {
  if [[ ! -f /usr/local/bin/cfssl ]]
  then
    curl -Lo /usr/local/bin/cfssl \
      "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_${OS}_${BINARY_ARACH}"
  fi

  if [[ ! -f /usr/local/bin/cfssljson ]]
  then
    curl -Lo /usr/local/bin/cfssljson \
      "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_${OS}_${BINARY_ARACH}"
  fi

  chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
}

function install_kubectl() { 
  local dest
  dest="/usr/local/bin/kubectl"
  if [[ ! -f ${dest} ]]
  then
    curl -Lo ${dest} https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/${OS}/${BINARY_ARACH}/kubectl
    chmod +x ${dest}
  fi
}

function install_misc() {
  apt-get update
  apt-get install -y \
    net-tools \
    jq
}

function install_helm() {
  local tar_filename
  tar_filename="helm-v${HELM_VERSION}-linux-${BINARY_ARACH}.tar.gz"
  if [[ ! -f ${tar_filename} ]]
  then
    curl -LO https://get.helm.sh/${tar_filename}
  fi
  
  tar -xf "${tar_filename}"
  cp "linux-${BINARY_ARACH}/helm" /usr/local/bin
}

function ensure_dir() {
  for _dir in ${ADDON_DIR} ${BASE_DIR} ${CERT_DIR} ${CONFIG_DIR} ${DOWNLOAD_DIR}
  do
    if [[ ! -d ${_dir} ]]
    then
      mkdir -p "${_dir}"
    fi
  done
}

ensure_dir
pushd "${DOWNLOAD_DIR}"
  install_cfssl
  install_kubectl
  install_misc
  install_helm
popd
