#!/bin/bash

# Source common functions if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -f "./common.sh" ]]; then
    source "./common.sh"
  else
    echo "common.sh not found. This script requires common functions."
    exit 1
  fi
fi

function install_rke2_server() {
  section "Installing RKE2 Server with Cilium as CNI"
  mkdir -p /etc/rancher/rke2
  cat <<EOF > /etc/rancher/rke2/config.yaml
token: mysupersecuretoken
cni: cilium
kube-apiserver-arg:
  - "service-node-port-range=80-32767"
tls-san:
  - $(hostname -I | awk '{print $1}')
EOF

  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
  systemctl enable rke2-server.service
  systemctl start rke2-server.service

  export PATH=$PATH:/var/lib/rancher/rke2/bin
  mkdir -p ~/.kube
  cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
  chmod 600 ~/.kube/config
  export KUBECONFIG=~/.kube/config
  echo -e "${GREEN}RKE2 server installed successfully${NC}"
}

function install_rke2_agent() {
  section "Installing RKE2 Agent (Worker Node)"
  
  # Prompt for server details
  read -p "Enter the RKE2 server IP address: " SERVER_IP
  read -p "Enter the RKE2 token: " TOKEN
  
  mkdir -p /etc/rancher/rke2
  cat <<EOF > /etc/rancher/rke2/config.yaml
server: https://${SERVER_IP}:9345
token: ${TOKEN}
EOF

  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
  systemctl enable rke2-agent.service
  systemctl start rke2-agent.service
  
  echo -e "${GREEN}RKE2 agent installed and joined to server ${SERVER_IP}${NC}"
}

function install_helm() {
  section "Installing Helm"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

function add_helm_repos() {
  section "Adding Helm Repositories"
  helm repo add cilium https://helm.cilium.io/
  helm repo add longhorn https://charts.longhorn.io
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo add jetstack https://charts.jetstack.io
  helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
  helm repo add traefik https://traefik.github.io/charts
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo add percona https://percona.github.io/percona-helm-charts/
  helm repo update
}

function install_cilium() {
  section "Installing Cilium"
  NODE_IP=$(hostname -I | awk '{print $1}')
  helm install cilium cilium/cilium --version 1.15.5 --namespace kube-system \
    --set kubeProxyReplacement=strict \
    --set k8sServiceHost=$NODE_IP \
    --set k8sServicePort=6443 \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
  
  echo -e "${GREEN}Cilium CNI installed${NC}"
}

function install_metallb() {
  section "Installing MetalLB"
  NODE_IP=$(hostname -I | awk '{print $1}')
  kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
  sleep 5
  cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: my-pool
  namespace: metallb-system
spec:
  addresses:
  - ${NODE_IP}/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv
  namespace: metallb-system
EOF

  echo -e "${GREEN}MetalLB load balancer installed${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running script directly - please select an option:"
  PS3='Select core component to install: '
  options=("RKE2 Server" "RKE2 Agent" "Helm" "Cilium" "MetalLB" "All Core Components" "Quit")
  
  select opt in "${options[@]}"; do
    case $opt in
      "RKE2 Server")
        install_rke2_server
        ;;
      "RKE2 Agent")
        install_rke2_agent
        ;;
      "Helm")
        install_helm
        add_helm_repos
        ;;
      "Cilium")
        install_cilium
        ;;
      "MetalLB")
        install_metallb
        ;;
      "All Core Components")
        install_rke2_server
        install_helm
        add_helm_repos
        install_cilium
        install_metallb
        break
        ;;
      "Quit")
        break
        ;;
      *) 
        echo "Invalid option $REPLY"
        ;;
    esac
  done
fi 