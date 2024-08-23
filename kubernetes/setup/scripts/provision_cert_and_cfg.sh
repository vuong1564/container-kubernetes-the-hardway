#!/usr/bin/env bash

set -euxo pipefail

source "$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/_variables.sh"

function _init_ca() {
  for _file in ca-config.json ca-csr.json
  do
    [[ -f ${_file} ]] && \
    echo "'${_file}' was existed. Please do a cleanup (rm -f ${PWD}/*)" \
    && exit 1
  done
  
  cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes The Hardway CA",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "Lab",
      "O": "Kubernetes The Hardway CA",
      "OU": "Infrastructure"
    }
  ]
}
EOF
  cfssl gencert -initca ca-csr.json | cfssljson -bare ca \
    && rm -f ca-csr.json ca.csr

  # CA singning profile
  cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF
}


function _create_admin_certificate() {
  cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "VN",
      "O": "system:masters",
      "OU": "Platform Engineering",
      "ST": "HCM"
    }
  ]
}
EOF

  cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin \
  && rm -f admin-csr.json admin.csr
}

function _create_kubelet_certificate() {
  # Group: https://kubernetes.io/docs/reference/access-authn-authz/authentication/#x509-client-certs
  # Username: https://kubernetes.io/docs/reference/access-authn-authz/authentication/#users-in-kubernetes
  for id in $(seq 1 ${NUM_WORKER_NODES})
  do
    instance="worker-${id}"
    internal_ip="${NETWORK}$((WORKER_IP_START + id))"
    cat > ${instance}-csr.json <<EOF
    {
      "CN": "system:node:${instance}",
      "key": {
        "algo": "rsa",
        "size": 2048
      },
      "names": [
        {
          "C": "VN",
          "L": "VN",
          "O": "system:nodes",
          "OU": "Platform Engineering",
          "ST": "HCM"
        }
      ]
    }
EOF

    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=${instance},${internal_ip} \
      -profile=kubernetes \
      ${instance}-csr.json | cfssljson -bare ${instance} \
    && rm -f ${instance}-csr.json ${instance}.csr
  done
}

function _create_controller_manager_certificate() {
  cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "VN",
      "O": "system:kube-controller-manager",
      "OU": "Platform Engineering",
      "ST": "HCM"
    }
  ]
}
EOF

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager \
  && rm -f kube-controller-manager-csr.json kube-controller-manager.csr
}

function _create_kube_proxy_certificate() {
  cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "VN",
      "O": "system:node-proxier",
      "OU": "Platform Engineering",
      "ST": "HCM"
    }
  ]
}
EOF
  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    kube-proxy-csr.json | cfssljson -bare kube-proxy \
  && rm -f kube-proxy-csr.json kube-proxy.csr
}

function _create_kube_scheduler_certificate() {
  cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "VN",
      "O": "system:kube-scheduler",
      "OU": "Platform Engineering",
      "ST": "HCM"
    }
  ]
}
EOF
  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    kube-scheduler-csr.json | cfssljson -bare kube-scheduler \
  && rm -f kube-scheduler-csr.json kube-scheduler.csr
}

function _create_kube_apiserver_cerficate() {
  # The Kubernetes API Server Certificate
  # The Kubernetes API server is automatically assigned the kubernetes internal dns name, 
  # which will be linked to the first IP address (10.32.0.1) from the address range (10.32.0.0/24) 
  # reserved for internal cluster services during the control plane bootstrapping lab.

  cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "VN",
      "O": "Kubernetes",
      "OU": "Platform Engineering",
      "ST": "HCM"
    }
  ]
}
EOF

  KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.default.svc.cluster.local

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -hostname=10.32.0.1,192.168.56.11,127.0.0.1,${KUBERNETES_HOSTNAMES} \
    -profile=kubernetes \
    kubernetes-csr.json | cfssljson -bare kubernetes \
  && rm -f kubernetes-csr.json kubernetes.csr
}

function _create_service_account_signing_keypair() {
  # The Service Account Key Pair
  # The Kubernetes Controller Manager leverages a key pair to generate and sign service account tokens as described 
  # in the managing service accounts documentation.
  # https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
  cat > service-account-csr.json <<EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "VN",
      "L": "VN",
      "O": "Kubernetes",
      "OU": "Platform Engineering",
      "ST": "HCM"
    }
  ]
}
EOF

  cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=ca-config.json \
    -profile=kubernetes \
    service-account-csr.json | cfssljson -bare service-account \
  && rm -f service-account-csr.json service-account.csr
}

function create_cert() {
  echo "[+] Initialize Certificate Authority Private Key and Certificate"
  _init_ca

  echo "[+] Generate Private Keys and Certificate"
  printf "\t * superadmin user\n"
  _create_admin_certificate

  printf "\t * kubelet\n"
  _create_kubelet_certificate

  printf "\t * kube-controller-manager\n"
  _create_controller_manager_certificate

  printf "\t * kube-proxy\n"
  _create_kube_proxy_certificate

  printf "\t * kube-scheduler\n"
  _create_kube_scheduler_certificate

  printf "\t * kube-apiserver\n"
  _create_kube_apiserver_cerficate

  printf "\t * ServiceAccount signing\n"
  _create_service_account_signing_keypair
}

function _generate_kubelet_configuration() {
  for idx in $(seq 1 ${NUM_WORKER_NODES}); do
    instance="${WORKER_PREFIX}${idx}"
    kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
      --certificate-authority=${CERT_DIR}/ca.pem \
      --embed-certs=true \
      --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
      --kubeconfig=${instance}.kubeconfig

    kubectl config set-credentials system:node:${instance} \
      --client-certificate=${CERT_DIR}/${instance}.pem \
      --client-key=${CERT_DIR}/${instance}-key.pem \
      --embed-certs=true \
      --kubeconfig=${instance}.kubeconfig

    kubectl config set-context default \
      --cluster=${KUBERNETES_CLUSTER_NAME} \
      --user=system:node:${instance} \
      --kubeconfig=${instance}.kubeconfig

    kubectl config use-context default --kubeconfig=${instance}.kubeconfig
  done
}

function _generate_kube_proxy_configuration() {
  kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
    --certificate-authority=${CERT_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_PUBLIC_ADDRESS}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=${CERT_DIR}/kube-proxy.pem \
    --client-key=${CERT_DIR}/kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=${KUBERNETES_CLUSTER_NAME} \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}

function _generate_kube_controller_manager_configuration() {
  kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
    --certificate-authority=${CERT_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=${CERT_DIR}/kube-controller-manager.pem \
    --client-key=${CERT_DIR}/kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=${KUBERNETES_CLUSTER_NAME} \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
  
function _generate_kube_scheduler_configuration() {
  kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
    --certificate-authority=${CERT_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=${CERT_DIR}/kube-scheduler.pem \
    --client-key=${CERT_DIR}/kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=${KUBERNETES_CLUSTER_NAME} \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}

function _generate_admin_configuration() {
 kubectl config set-cluster ${KUBERNETES_CLUSTER_NAME} \
    --certificate-authority=${CERT_DIR}/ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=${CERT_DIR}/admin.pem \
    --client-key=${CERT_DIR}/admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=${KUBERNETES_CLUSTER_NAME} \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}

function generate_kubernetes_configuration() {
  _generate_kubelet_configuration
  _generate_kube_proxy_configuration
  _generate_kube_controller_manager_configuration
  _generate_kube_scheduler_configuration
  _generate_admin_configuration
}

pushd "${CERT_DIR}"
create_cert
popd

pushd "${CONFIG_DIR}"
generate_kubernetes_configuration
popd