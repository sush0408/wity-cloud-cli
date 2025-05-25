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

# Export variables and functions
export GREEN YELLOW BLUE RED NC

# Run basic setup for direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo -e "${GREEN}Wity Cloud Deploy - Common Functions${NC}"
  echo -e "${YELLOW}This script provides common functions for other scripts${NC}"
  echo -e "${YELLOW}It should be sourced by other scripts, not executed directly${NC}"
  
  # If still running, perform basic setup
  check_root
  setup_path
  
  # Check if we're on a server or agent node
  if [[ -f /var/lib/rancher/rke2/server/node-token ]]; then
    echo -e "${GREEN}This is an RKE2 server node${NC}"
  elif [[ -f /etc/rancher/rke2/config.yaml ]] && grep -q "server:" /etc/rancher/rke2/config.yaml; then
    echo -e "${GREEN}This is an RKE2 agent node${NC}"
  else
    echo -e "${YELLOW}RKE2 not installed on this node${NC}"
  fi
fi 