#!/bin/bash

# Common variables and functions used by all scripts

# Colors for console output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Section header function
function section() {
  echo -e "\n${YELLOW}==> $1${NC}"
}

# Setup environment for RKE2
function setup_k8s_env() {
  # Add RKE2 binaries to PATH
  if [[ -d /var/lib/rancher/rke2/bin ]]; then
    export PATH=$PATH:/var/lib/rancher/rke2/bin
  fi
  
  # Set KUBECONFIG if RKE2 is installed
  if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  fi
  
  # Create symlinks for easier access if they don't exist
  if [[ -f /var/lib/rancher/rke2/bin/kubectl ]] && [[ ! -f /usr/local/bin/kubectl ]]; then
    ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl 2>/dev/null || true
  fi
  
  if [[ -f /var/lib/rancher/rke2/bin/crictl ]] && [[ ! -f /usr/local/bin/crictl ]]; then
    ln -sf /var/lib/rancher/rke2/bin/crictl /usr/local/bin/crictl 2>/dev/null || true
  fi
}

# Check if we're running as root
function check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
  fi
}

# Check dependencies
function check_dependencies() {
  local missing=0
  
  for cmd in "$@"; do
    if ! command -v "$cmd" &> /dev/null; then
      echo -e "${RED}Command not found: $cmd${NC}"
      missing=1
    fi
  done
  
  if [[ $missing -eq 1 ]]; then
    echo -e "${YELLOW}Please install missing dependencies and try again${NC}"
    exit 1
  fi
}

# Install essential system dependencies
function install_essential_dependencies() {
  section "Installing essential system dependencies"
  
  echo -e "${YELLOW}Updating package lists...${NC}"
  apt-get update
  
  echo -e "${YELLOW}Installing essential packages...${NC}"
  apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    vim \
    nano \
    htop \
    net-tools \
    dnsutils
  
  echo -e "${GREEN}Essential dependencies installed successfully${NC}"
}

# Check if RKE2 is running
function check_rke2_running() {
  if ! systemctl is-active --quiet rke2-server; then
    echo -e "${RED}RKE2 server is not running${NC}"
    echo -e "${YELLOW}Run 'core.sh' first to install RKE2${NC}"
    return 1
  fi
  return 0
}

# Check if kubectl can access the cluster
function check_kubectl() {
  # First ensure environment is set up
  setup_k8s_env
  
  if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    echo -e "${YELLOW}Make sure KUBECONFIG is set correctly${NC}"
    
    # Try to fix KUBECONFIG if possible
    if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
      export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
      if kubectl get nodes &> /dev/null; then
        echo -e "${GREEN}KUBECONFIG fixed${NC}"
        return 0
      fi
    fi
    
    return 1
  fi
  return 0
}

# Setup PATH for RKE2 binaries if needed
function setup_path() {
  if [[ ! "$PATH" =~ "/var/lib/rancher/rke2/bin" ]]; then
    export PATH=$PATH:/var/lib/rancher/rke2/bin
    echo -e "${GREEN}Added RKE2 binaries to PATH${NC}"
  fi
}

# Get the current node's IP address
function get_node_ip() {
  hostname -I | awk '{print $1}'
}

# Check if a Helm release exists
function helm_release_exists() {
  local release_name=$1
  local namespace=${2:-default}
  
  helm list -n "$namespace" | grep -q "^$release_name" 2>/dev/null
}

# Check if a namespace exists
function namespace_exists() {
  local namespace=$1
  kubectl get namespace "$namespace" &>/dev/null
}

# Safe Helm install with existing installation check
function safe_helm_install() {
  local release_name=$1
  local chart=$2
  local namespace=$3
  shift 3
  local helm_args=("$@")
  
  if helm_release_exists "$release_name" "$namespace"; then
    echo -e "${GREEN}$release_name is already installed in namespace $namespace${NC}"
    
    # Check if pods are running
    if kubectl get pods -n "$namespace" | grep -q "Running" 2>/dev/null; then
      echo -e "${GREEN}$release_name is running properly${NC}"
      return 0
    else
      echo -e "${YELLOW}$release_name is installed but may not be running properly${NC}"
      
      # Check if we're in non-interactive mode (for batch installations)
      if [[ "${BATCH_MODE:-false}" == "true" ]]; then
        echo -e "${YELLOW}Batch mode: Automatically reinstalling $release_name...${NC}"
        helm uninstall "$release_name" -n "$namespace" 2>/dev/null || true
        sleep 5
      else
        read -p "Do you want to reinstall $release_name? [y/N]: " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
          return 0
        fi
        
        echo -e "${YELLOW}Uninstalling existing $release_name...${NC}"
        helm uninstall "$release_name" -n "$namespace" 2>/dev/null || true
        sleep 5
      fi
    fi
  fi
  
  # Check if namespace exists but no Helm release
  if namespace_exists "$namespace" && ! helm_release_exists "$release_name" "$namespace"; then
    echo -e "${YELLOW}Namespace $namespace exists but no $release_name release found${NC}"
    
    # Check if we're in non-interactive mode
    if [[ "${BATCH_MODE:-false}" == "true" ]]; then
      echo -e "${YELLOW}Batch mode: Automatically cleaning up namespace $namespace...${NC}"
      kubectl delete namespace "$namespace" --ignore-not-found=true
      sleep 10
    else
      read -p "Do you want to clean up namespace $namespace and reinstall? [y/N]: " cleanup
      if [[ "$cleanup" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleaning up existing namespace...${NC}"
        kubectl delete namespace "$namespace" --ignore-not-found=true
        sleep 10
      fi
    fi
  fi
  
  # Proceed with installation
  echo -e "${GREEN}Installing $release_name...${NC}"
  helm install "$release_name" "$chart" --namespace "$namespace" --create-namespace "${helm_args[@]}"
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}$release_name installed successfully${NC}"
    return 0
  else
    echo -e "${RED}Failed to install $release_name${NC}"
    return 1
  fi
}

# Check if a deployment is ready
function wait_for_deployment() {
  local deployment=$1
  local namespace=${2:-default}
  local timeout=${3:-300}
  
  echo -e "${YELLOW}Waiting for $deployment to be ready...${NC}"
  if kubectl wait --for=condition=Available deployment/"$deployment" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
    echo -e "${GREEN}$deployment is ready${NC}"
    return 0
  else
    echo -e "${YELLOW}$deployment is taking longer than expected to be ready${NC}"
    return 1
  fi
}

# Create setup script for easy environment configuration
function create_setup_script() {
  cat <<'EOF' > /root/setup-k8s-env.sh
#!/bin/bash
# RKE2 Environment Setup Script
# Source this script to configure your environment for RKE2

# Add RKE2 binaries to PATH
if [[ -d /var/lib/rancher/rke2/bin ]]; then
  export PATH=$PATH:/var/lib/rancher/rke2/bin
fi

# Set KUBECONFIG
if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
fi

# Create convenient aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'

echo "RKE2 environment configured!"
echo "KUBECONFIG: $KUBECONFIG"
echo "kubectl available: $(which kubectl 2>/dev/null || echo 'Not found')"
EOF
  
  chmod +x /root/setup-k8s-env.sh
  echo -e "${GREEN}Created /root/setup-k8s-env.sh for easy environment setup${NC}"
}

# Export variables and functions
export GREEN YELLOW BLUE RED NC

# Automatically set up environment when this script is sourced
setup_k8s_env

# Run basic setup for direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo -e "${GREEN}Wity Cloud Deploy - Common Functions${NC}"
  echo -e "${YELLOW}This script provides common functions for other scripts${NC}"
  echo -e "${YELLOW}It should be sourced by other scripts, not executed directly${NC}"
  
  # If still running, perform basic setup
  check_root
  setup_k8s_env
  create_setup_script
  
  # Check if we're on a server or agent node
  if [[ -f /var/lib/rancher/rke2/server/node-token ]]; then
    echo -e "${GREEN}This is an RKE2 server node${NC}"
  elif [[ -f /etc/rancher/rke2/config.yaml ]] && grep -q "server:" /etc/rancher/rke2/config.yaml; then
    echo -e "${GREEN}This is an RKE2 agent node${NC}"
  else
    echo -e "${YELLOW}RKE2 not installed on this node${NC}"
  fi
  
  echo -e "\n${YELLOW}To configure your shell environment, run:${NC}"
  echo -e "source /root/setup-k8s-env.sh"
fi 