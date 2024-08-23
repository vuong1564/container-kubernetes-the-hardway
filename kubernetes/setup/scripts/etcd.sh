#!/usr/bin/env bash

set -euxo pipefail

source "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/_variables.sh"

function setup_etcd() {
  local etcd_name cluster_name
  etcd_name=$(hostname -s)
  cluster_name="etcd-cluster-0"

  curl -LO https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${BINARY_ARACH}.tar.gz
  tar -xvf etcd-v${ETCD_VERSION}-linux-${BINARY_ARACH}.tar.gz
  mv etcd-v${ETCD_VERSION}-linux-${BINARY_ARACH}/etcd* /usr/local/bin/

  mkdir -p /etc/etcd /var/lib/etcd
  chmod 700 /var/lib/etcd
  cp "${CERT_DIR}/ca.pem" "${CERT_DIR}/kubernetes-key.pem" "${CERT_DIR}/kubernetes.pem" /etc/etcd/

  cat <<EOF | tee /etc/systemd/system/etcd.service
  [Unit]
  Description=etcd
  Documentation=https://github.com/coreos

  [Service]
  Type=notify
  ExecStart=/usr/local/bin/etcd \\
    --name ${etcd_name} \\
    --cert-file=/etc/etcd/kubernetes.pem \\
    --key-file=/etc/etcd/kubernetes-key.pem \\
    --peer-cert-file=/etc/etcd/kubernetes.pem \\
    --peer-key-file=/etc/etcd/kubernetes-key.pem \\
    --trusted-ca-file=/etc/etcd/ca.pem \\
    --peer-trusted-ca-file=/etc/etcd/ca.pem \\
    --peer-client-cert-auth \\
    --client-cert-auth \\
    --initial-advertise-peer-urls https://${CONTROLLER_INTERNAL_IP}:2380 \\
    --listen-peer-urls https://${CONTROLLER_INTERNAL_IP}:2380 \\
    --listen-client-urls https://${CONTROLLER_INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
    --advertise-client-urls https://${CONTROLLER_INTERNAL_IP}:2379 \\
    --initial-cluster-token ${cluster_name} \\
    --initial-cluster controller-1=https://192.168.56.11:2380 \\
    --initial-cluster-state new \\
    --data-dir=/var/lib/etcd
  Restart=on-failure
  RestartSec=5

  [Install]
  WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable etcd
  systemctl start etcd
}

function etcd_verify() {
  ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/etcd/ca.pem \
    --cert=/etc/etcd/kubernetes.pem \
    --key=/etc/etcd/kubernetes-key.pem
}

pushd "${DOWNLOAD_DIR}"
setup_etcd
sleep 2s
etcd_verify
popd