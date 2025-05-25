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

# Function to ask for approval (if not already defined)
if ! declare -f ask_approval > /dev/null; then
  ask_approval() {
    local message=$1
    if [[ "${BATCH_MODE:-false}" == "true" ]]; then
      echo -e "${BLUE}$message${NC} - Auto-approved (batch mode)"
      return 0
    fi
    echo -e "${BLUE}$message${NC} (y/n)"
    read -r approval
    if [[ ! $approval =~ ^[Yy]$ ]]; then
      echo "Skipping this step..."
      return 1
    fi
    return 0
  }
fi

function install_rke2_server() {
  section "Installing RKE2 Server with Cilium as CNI"
  
  # Increase file limits to prevent "Too many open files" error
  echo -e "${YELLOW}Optimizing system limits for RKE2...${NC}"
  
  # Set temporary limits for current session
  ulimit -n 65536
  ulimit -u 32768
  
  # Create permanent limits configuration
  cat > /etc/security/limits.d/99-rke2.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
root soft nofile 65536
root hard nofile 65536
root soft nproc 32768
root hard nproc 32768
EOF

  # Apply sysctl optimizations
  cat > /etc/sysctl.d/99-rke2.conf << EOF
fs.inotify.max_user_watches=524288
fs.file-max=131072
vm.max_map_count=262144
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF

  sysctl --system
  
  mkdir -p /etc/rancher/rke2
  cat <<EOF > /etc/rancher/rke2/config.yaml
token: mysupersecuretoken
cni: cilium
kube-apiserver-arg:
  - "service-node-port-range=80-32767"
tls-san:
  - $(hostname -I | awk '{print $1}')
EOF

  echo -e "${YELLOW}Downloading and installing RKE2...${NC}"
  curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="server" sh -
  
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to download/install RKE2${NC}"
    return 1
  fi
  
  systemctl enable rke2-server.service
  systemctl start rke2-server.service

  # Wait for RKE2 to be ready with better error handling
  echo -e "${YELLOW}Waiting for RKE2 server to be ready...${NC}"
  
  # Wait up to 5 minutes for RKE2 to start
  local timeout=300
  local elapsed=0
  local interval=10
  
  while [[ $elapsed -lt $timeout ]]; do
    if systemctl is-active --quiet rke2-server; then
      echo -e "${GREEN}RKE2 server is active${NC}"
      break
    fi
    
    echo -e "${YELLOW}Waiting for RKE2 server to start... (${elapsed}s/${timeout}s)${NC}"
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  if [[ $elapsed -ge $timeout ]]; then
    echo -e "${RED}RKE2 server failed to start within ${timeout} seconds${NC}"
    echo -e "${YELLOW}Checking RKE2 server logs:${NC}"
    journalctl -u rke2-server --no-pager -l | tail -20
    return 1
  fi
  
  # Additional wait for Kubernetes API to be ready
  sleep 30

  # Set up environment
  export PATH=$PATH:/var/lib/rancher/rke2/bin
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  
  # Create symlinks for easier access
  ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl 2>/dev/null || true
  ln -sf /var/lib/rancher/rke2/bin/crictl /usr/local/bin/crictl 2>/dev/null || true
  
  # Create the environment setup script
  create_setup_script
  
  # Also create a copy in ~/.kube for compatibility
  mkdir -p ~/.kube
  cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
  chmod 600 ~/.kube/config
  
  # Verify installation
  if kubectl get nodes &>/dev/null; then
    echo -e "${GREEN}RKE2 server installed successfully${NC}"
    kubectl get nodes
  else
    echo -e "${RED}RKE2 installation may have issues - kubectl cannot connect${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}To configure your shell environment, run:${NC}"
  echo -e "source /root/setup-k8s-env.sh"
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
  
  # Check if Cilium is already installed by RKE2
  if helm list -n kube-system | grep -q "rke2-cilium"; then
    echo -e "${YELLOW}Cilium is already installed by RKE2 (rke2-cilium)${NC}"
    
    # Check if Cilium pods are running properly
    if kubectl get pods -n kube-system -l k8s-app=cilium | grep -q "Running"; then
      echo -e "${GREEN}RKE2's Cilium is running properly${NC}"
      
      if ask_approval "Do you want to replace RKE2's Cilium with Helm-managed Cilium?"; then
        echo -e "${YELLOW}Removing RKE2's Cilium installation...${NC}"
        # Note: We cannot easily remove RKE2's built-in Cilium, so we'll skip this
        echo -e "${YELLOW}Cannot safely remove RKE2's built-in Cilium. Skipping Helm installation.${NC}"
        echo -e "${GREEN}Using existing RKE2 Cilium installation${NC}"
        return 0
      else
        echo -e "${GREEN}Keeping existing RKE2 Cilium installation${NC}"
        return 0
      fi
    else
      echo -e "${YELLOW}RKE2's Cilium appears to have issues. Checking for conflicts...${NC}"
    fi
  fi
  
  # Check if there's a conflicting Helm Cilium installation
  if helm list -n kube-system | grep -q "^cilium"; then
    echo -e "${YELLOW}Found existing Helm Cilium installation${NC}"
    if ask_approval "Do you want to remove the existing Helm Cilium installation?"; then
      echo -e "${YELLOW}Removing existing Helm Cilium...${NC}"
      helm uninstall cilium -n kube-system || true
      sleep 10
    else
      echo -e "${GREEN}Keeping existing Cilium installation${NC}"
      return 0
    fi
  fi
  
  # Check for ServiceAccount conflicts
  if kubectl get serviceaccount cilium -n kube-system &>/dev/null; then
    echo -e "${YELLOW}Found existing Cilium ServiceAccount with conflicting ownership${NC}"
    
    # Check if it belongs to rke2-cilium
    OWNER=$(kubectl get serviceaccount cilium -n kube-system -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || echo "")
    
    if [[ "$OWNER" == "rke2-cilium" ]]; then
      echo -e "${YELLOW}ServiceAccount belongs to RKE2's Cilium installation${NC}"
      echo -e "${YELLOW}Cannot install Helm Cilium over RKE2's Cilium. Using existing installation.${NC}"
      return 0
    else
      if ask_approval "Do you want to remove the conflicting Cilium resources?"; then
        echo -e "${YELLOW}Removing conflicting Cilium resources...${NC}"
        kubectl delete serviceaccount cilium -n kube-system --ignore-not-found=true
        kubectl delete clusterrole cilium --ignore-not-found=true
        kubectl delete clusterrolebinding cilium --ignore-not-found=true
        kubectl delete daemonset cilium -n kube-system --ignore-not-found=true
        sleep 10
      else
        echo -e "${YELLOW}Cannot proceed with conflicting resources. Skipping Cilium installation.${NC}"
        return 1
      fi
    fi
  fi
  
  # Proceed with Cilium installation
  NODE_IP=$(hostname -I | awk '{print $1}')
  echo -e "${GREEN}Installing Cilium with Helm...${NC}"
  
  helm install cilium cilium/cilium --version 1.15.5 --namespace kube-system \
    --set kubeProxyReplacement=strict \
    --set k8sServiceHost=$NODE_IP \
    --set k8sServicePort=6443 \
    --set hubble.enabled=true \
    --set hubble.relay.enabled=true \
    --set hubble.ui.enabled=true
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Cilium CNI installed successfully${NC}"
  else
    echo -e "${RED}Failed to install Cilium${NC}"
    return 1
  fi
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

function check_cilium_status() {
  section "Checking Cilium Status"
  
  echo -e "${YELLOW}Checking for Cilium installations...${NC}"
  
  # Check for RKE2's Cilium
  if helm list -n kube-system | grep -q "rke2-cilium"; then
    echo -e "${GREEN}✓ RKE2's Cilium found${NC}"
    helm list -n kube-system | grep "rke2-cilium"
  else
    echo -e "${YELLOW}✗ RKE2's Cilium not found${NC}"
  fi
  
  # Check for Helm-managed Cilium
  if helm list -n kube-system | grep -q "^cilium"; then
    echo -e "${GREEN}✓ Helm-managed Cilium found${NC}"
    helm list -n kube-system | grep "^cilium"
  else
    echo -e "${YELLOW}✗ Helm-managed Cilium not found${NC}"
  fi
  
  # Check Cilium pods
  echo -e "\n${YELLOW}Cilium pods status:${NC}"
  kubectl get pods -n kube-system -l k8s-app=cilium -o wide 2>/dev/null || echo "No Cilium pods found"
  
  # Check Cilium connectivity
  echo -e "\n${YELLOW}Cilium connectivity test (if available):${NC}"
  if kubectl get pods -n kube-system -l k8s-app=cilium | grep -q "Running"; then
    echo -e "${GREEN}Cilium pods are running${NC}"
    
    # Try to get Cilium status if cilium CLI is available
    if command -v cilium &> /dev/null; then
      echo -e "${YELLOW}Running Cilium status check...${NC}"
      cilium status || echo "Cilium CLI status check failed"
    else
      echo -e "${YELLOW}Cilium CLI not available for detailed status${NC}"
    fi
  else
    echo -e "${RED}Cilium pods are not running properly${NC}"
  fi
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running script directly - please select an option:"
  PS3='Select core component to install: '
  options=("RKE2 Server" "RKE2 Agent" "Helm" "Cilium" "MetalLB" "Check Cilium Status" "All Core Components" "Quit")
  
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
      "Check Cilium Status")
        check_cilium_status
        ;;
      "All Core Components")
        install_rke2_server
        install_helm
        add_helm_repos
        
        # Check if RKE2's Cilium is working before trying to install via Helm
        echo -e "${YELLOW}Checking RKE2's built-in Cilium status...${NC}"
        if helm list -n kube-system | grep -q "rke2-cilium" && kubectl get pods -n kube-system -l k8s-app=cilium | grep -q "Running"; then
          echo -e "${GREEN}RKE2's Cilium is already running properly. Skipping Helm Cilium installation.${NC}"
        else
          install_cilium
        fi
        
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