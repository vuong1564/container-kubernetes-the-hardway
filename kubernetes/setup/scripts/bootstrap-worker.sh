#!/usr/bin/env bash

set -euxo pipefail

source "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/_variables.sh"

function prerequisite() {
  apt-get update && \
  apt-get -y install socat conntrack ipset
  swapoff -a
}

function setup_cni_plugins() {
  local cni_tar_filename
  cni_tar_filename="cni-plugins-linux-${BINARY_ARACH}-v${CNI_PLUGINS_VERSION}.tgz"
  
  for _dir in /etc/cni/net.d /opt/cni/bin
  do
    if [[ ! -d ${_dir} ]]
    then
      mkdir -p /etc/cni/net.d /opt/cni/bin 
    fi
  done

  if [[ ! -f ${cni_tar_filename} ]]
  then
    curl -LO https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/${cni_tar_filename}
    tar -xvf ${cni_tar_filename} -C /opt/cni/bin/
  fi
}

function setup_kubelet() {
  for _dir in /var/lib/kubelet /var/lib/kubernetes/ /var/run/kubernetes
  do
    if [[ ! -d ${_dir} ]]
    then
      mkdir -p /var/lib/kubelet /var/lib/kubernetes/ /var/run/kubernetes
    fi
  done

  if [[ ! -f /usr/local/bin/kubelet ]]
  then
    curl -Lo /usr/local/bin/kubelet https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/${BINARY_ARACH}/kubelet
    chmod +x /usr/local/bin/kubelet
  fi

  cp ${CERT_DIR}/${HOSTNAME}-key.pem ${CERT_DIR}/${HOSTNAME}.pem /var/lib/kubelet/
  cp ${CERT_DIR}/ca.pem /var/lib/kubernetes/
  cp ${CONFIG_DIR}/${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig

  cat <<EOF | tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "${CLUSTER_DNS_IP}"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${HOSTNAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${HOSTNAME}-key.pem"
EOF

  cat <<EOF | tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable kubelet
  systemctl start kubelet

}

function setup_kube_proxy() {
  if [[ ! -d /var/lib/kube-proxy ]]
  then
      mkdir -p /var/lib/kube-proxy
  fi

  if [[ ! -f /usr/local/bin/kube-proxy ]]
  then
    curl -Lo /usr/local/bin/kube-proxy https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/${BINARY_ARACH}/kube-proxy
    chmod +x /usr/local/bin/kube-proxy
  fi


  cp ${CONFIG_DIR}/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
  cat <<EOF | tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "${POD_IP_RANGE}"
EOF

cat <<EOF | tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # Start the Worker Services
  systemctl daemon-reload
  systemctl enable kube-proxy
  systemctl start kube-proxy
}

function setup_containerd() {
  local crictl_tar_filename containerd_tar_filename
  crictl_tar_filename="crictl-v${CRICTR_VERSION}-linux-${BINARY_ARACH}.tar.gz"
  if [[ ! -f ${crictl_tar_filename} ]]
  then
    curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTR_VERSION}/${crictl_tar_filename}
  fi
  tar -C /usr/local/bin -xf ${crictl_tar_filename}
  chmod +x /usr/local/bin/crictl

  if [[ ! -f /usr/local/bin/runc ]]
  then
    curl -Lo /usr/local/bin/runc https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${BINARY_ARACH}
    chmod +x /usr/local/bin/runc
  fi

  containerd_tar_filename="containerd-${CONTAINERD_VERSION}-linux-${BINARY_ARACH}.tar.gz"
  if [[ ! -f ${containerd_tar_filename} ]]
  then
    curl -LO https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/${containerd_tar_filename} 
  fi
  
  if [[ ! -f /bin/containerd ]]
  then
    tar -xf ${containerd_tar_filename}
    chmod +x bin/*
    cp bin/containerd* /bin/
  fi
  
  # Generate 'containerd' default configuration
  if [[ ! -d /etc/containerd/ ]]
  then
    mkdir -p /etc/containerd/
  fi
  containerd config default | tee /etc/containerd/config.toml
  
cat <<EOF | tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable containerd
  systemctl start containerd
}

# # Configure CNI Networking
# curl https://projectcalico.docs.tigera.io/manifests/calico.yaml -O
#   # update CALICO_IPV4POOL_CIDR to match Pod CIDR (10.200.0.0/16)


# Configure containerd

pushd "${DOWNLOAD_DIR}"
setup_cni_plugins
setup_containerd
setup_kubelet
setup_kube_proxy
popd
# Setup Calico