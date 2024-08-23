#!/usr/bin/env bash

set -euxo pipefail

# shellcheck disable=SC1091
source "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/_variables.sh"

function deploy_coredns() {
  kubectl apply \
    --kubeconfig "${ADMIN_KUBECONFIG}" \
    -n kube-system \
    -f "${ADDON_DIR}/core-dns-1.9.1.yaml"
}

function deploy_metallb() {
  helm upgrade --install --namespace kube-system \
    --repo https://metallb.github.io/metallb \
    --kubeconfig "${ADMIN_KUBECONFIG}" \
    -f "${ADDON_DIR}/metallab-values.yaml" \
    --wait metallb metallb
}

function deploy_external_dns() {
  helm upgrade --install \
    --kubeconfig "${ADMIN_KUBECONFIG}" \
    --repo https://kubernetes-sigs.github.io/external-dns/ \
    --version 1.9.0 \
    -n kube-system \
    -f "${ADDON_DIR}/external-dns-values.yaml" \
    external-dns external-dns
}

function deploy_cert_manager() {
  helm upgrade --install \
    --kubeconfig "${ADMIN_KUBECONFIG}" \
    --repo https://charts.jetstack.io \
    cert-manager cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.8.0 \
    -f "${ADDON_DIR}/cert-manager-values.yaml"

  kubectl --kubeconfig "${CONFIG_DIR}/admin.kubeconfig" \
    apply -f "${ADDON_DIR}/cert-manager/issuers.yaml"
}

function deploy_nginx_ingress_controller() {
  helm upgrade --install \
    --kubeconfig "${ADMIN_KUBECONFIG}" \
    --version 4.1.1 \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    -f "${ADDON_DIR}/nginx-ingress-values.yaml" \
    ingress-nginx ingress-nginx
}

function deploy_metrics_server() {
  helm upgrade --install \
    --kubeconfig "${ADMIN_KUBECONFIG}" \
    --repo https://kubernetes-sigs.github.io/metrics-server \
    --version 3.8.2 \
    --set hostNetwork.enabled="true" \
    --namespace kube-system \
    metrics-server metrics-server
}

function deploy_local_path_provisioner() {
  kubectl apply --kubeconfig "${ADMIN_KUBECONFIG}" \
    -f "${ADDON_DIR}/local-path-storage.yaml"
}

deploy_coredns
deploy_metrics_server
