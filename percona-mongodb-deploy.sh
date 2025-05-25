#!/bin/bash

# Percona MongoDB Complete Deployment Script
# Integrates with the Wity Cloud Deploy framework

# Source common functions
if [[ -f "./common.sh" ]]; then
  source "./common.sh"
else
  echo "common.sh not found. This script requires common functions."
  exit 1
fi

# Source monitoring functions for PMM
if [[ -f "./monitoring.sh" ]]; then
  source "./monitoring.sh"
else
  echo "monitoring.sh not found. PMM installation will be skipped."
fi

# Source database functions
if [[ -f "./databases.sh" ]]; then
  source "./databases.sh"
else
  echo "databases.sh not found. This script requires database functions."
  exit 1
fi

# Colors for output (already defined in common.sh, but ensuring they're available)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to ask for approval (interactive mode)
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

# System preparation function
function prepare_system() {
  section "Preparing system for Percona MongoDB deployment"
  
  if ask_approval "Do you want to update system packages and prepare the system?"; then
    echo -e "${YELLOW}Updating system packages...${NC}"
    apt-get update && apt-get upgrade -y
    
    # Install essential packages
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
      apt-transport-https

    # Tune system parameters for MongoDB
    echo "Applying system parameters for MongoDB..."
    cat > /etc/sysctl.d/99-mongodb.conf << EOF
vm.swappiness=1
fs.inotify.max_user_watches=524288
fs.file-max=131072
vm.max_map_count=262144
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF

    sysctl --system

    # Mount filesystems with noatime for better performance
    if ! grep -q "noatime" /etc/fstab; then
      echo "Configuring filesystem mount options for better performance..."
      sed -i 's/defaults/defaults,noatime/g' /etc/fstab
    fi
    
    echo -e "${GREEN}System preparation completed${NC}"
  fi
}

# Network components setup
function setup_network_components() {
  section "Setting up network components (MetalLB and cert-manager)"
  
  if ask_approval "Do you want to set up network components?"; then
    echo -e "${YELLOW}Setting up MetalLB and cert-manager...${NC}"
    
    # Check for existing MetalLB
    if kubectl get namespace metallb-system &>/dev/null; then
      if ask_approval "MetalLB is already installed. Do you want to remove it and reinstall?"; then
        echo "Removing existing MetalLB..."
        kubectl delete namespace metallb-system --timeout=60s || true
        sleep 10
      fi
    fi
    
    # Check for existing cert-manager
    if kubectl get namespace cert-manager &>/dev/null; then
      if ask_approval "cert-manager is already installed. Do you want to remove it and reinstall?"; then
        echo "Removing existing cert-manager..."
        kubectl delete namespace cert-manager --timeout=60s || true
        sleep 10
      fi
    fi
    
    echo "Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
    
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.2/cert-manager.yaml

    # Wait for cert-manager to be ready
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app=cert-manager --timeout=120s || {
      echo -e "${RED}Cert-manager failed to become ready in the allotted time. Continuing anyway...${NC}"
    }
    
    # Wait for MetalLB controller and webhook to be ready
    echo "Waiting for MetalLB controller to be ready..."
    kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb,component=controller --timeout=120s || {
      echo -e "${RED}MetalLB controller failed to become ready in the allotted time. Continuing anyway...${NC}"
    }
    
    echo "Waiting for MetalLB webhook to be ready..."
    kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb,component=webhook --timeout=120s || {
      echo -e "${RED}MetalLB webhook failed to become ready in the allotted time. Trying to continue...${NC}"
    }
    
    # Additional delay to ensure webhook is fully functional
    echo "Giving additional time for webhook to be fully operational..."
    sleep 20

    # Configure metallb address pool
    SERVER_IP=$(hostname -I | awk '{print $1}')
    IP_PREFIX=$(echo $SERVER_IP | cut -d. -f1-3)

    mkdir -p infrastructure/k8s/metallb
    cat > infrastructure/k8s/metallb/metallb-config.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IP_PREFIX}.240-${IP_PREFIX}.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF

    # Check if MetalLB config already exists
    if kubectl get ipaddresspool -n metallb-system first-pool &>/dev/null; then
      if ask_approval "MetalLB configuration already exists. Do you want to replace it?"; then
        kubectl delete ipaddresspool -n metallb-system first-pool || true
        kubectl delete l2advertisement -n metallb-system l2-advert || true
        sleep 5
      fi
    fi

    # Apply the MetalLB config with retry logic
    echo "Applying MetalLB configuration..."
    MAX_RETRIES=5
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      if kubectl apply -f infrastructure/k8s/metallb/metallb-config.yaml; then
        echo "MetalLB configuration applied successfully."
        break
      else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
          echo "Failed to apply MetalLB configuration. Retrying in 10 seconds... (Attempt $RETRY_COUNT of $MAX_RETRIES)"
          sleep 10
        else
          echo -e "${RED}Failed to apply MetalLB configuration after $MAX_RETRIES attempts. Continuing anyway...${NC}"
        fi
      fi
    done
    
    echo -e "${GREEN}Network components setup completed${NC}"
  fi
}

# Complete deployment function
function deploy_complete_stack() {
  section "Complete Percona MongoDB Stack Deployment"
  
  echo -e "${GREEN}Percona MongoDB Complete Deployment${NC}"
  echo "=================================================="
  echo "This will deploy:"
  echo "- Percona MongoDB with Operator"
  echo "- PMM (Percona Monitoring and Management)"
  echo "- Automated backups"
  echo "- Network components (MetalLB, cert-manager)"
  echo ""

  # Check if running as root
  check_root

  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster. Please ensure RKE2 is running.${NC}"
    echo -e "${YELLOW}Run './core.sh' first to install RKE2${NC}"
    exit 1
  fi

  # System preparation
  prepare_system

  # Setup network components
  setup_network_components

  # Install PMM Server first (if monitoring.sh is available)
  if declare -f install_pmm_server > /dev/null; then
    if ask_approval "Do you want to install PMM Server for monitoring?"; then
      install_pmm_server
    fi
  else
    echo -e "${YELLOW}PMM installation function not available. Skipping PMM setup.${NC}"
  fi

  # Install Percona MongoDB
  if ask_approval "Do you want to install Percona MongoDB with Operator?"; then
    install_mongodb_percona
  fi

  # Final status check
  if ask_approval "Do you want to check the deployment status?"; then
    section "Deployment Status Summary"
    
    echo -e "${YELLOW}Checking MongoDB cluster status...${NC}"
    kubectl get psmdb -n pgo 2>/dev/null || echo "No MongoDB clusters found"
    
    echo -e "${YELLOW}Checking MongoDB pods...${NC}"
    kubectl get pods -n pgo 2>/dev/null || echo "No MongoDB pods found"
    
    echo -e "${YELLOW}Checking PMM Server status...${NC}"
    kubectl get pods -n monitoring -l app=pmm-server 2>/dev/null || echo "No PMM Server found"
    
    echo -e "${YELLOW}Checking network components...${NC}"
    kubectl get pods -n metallb-system 2>/dev/null || echo "No MetalLB found"
    kubectl get pods -n cert-manager 2>/dev/null || echo "No cert-manager found"
  fi

  echo -e "${GREEN}Complete deployment finished!${NC}"
  echo "=================================================="
  echo "Access Information:"
  echo ""
  echo "MongoDB:"
  echo "  - Connection: mongodb://databaseAdmin:databaseAdmin123456@psmdb-mongos.pgo.svc.cluster.local/admin"
  echo "  - Namespace: pgo"
  echo ""
  echo "PMM Monitoring:"
  echo "  - Access: kubectl port-forward svc/pmm-server 8080:80 -n monitoring"
  echo "  - URL: http://localhost:8080"
  echo "  - Username: admin"
  echo "  - Password: admin-password"
  echo ""
  echo "Useful Commands:"
  echo "  - Check MongoDB: kubectl get psmdb -n pgo"
  echo "  - Check pods: kubectl get pods -n pgo"
  echo "  - MongoDB logs: kubectl logs -n pgo <pod-name>"
  echo "  - PMM logs: kubectl logs -n monitoring -l app=pmm-server"
  echo "=================================================="
}

# Cleanup function
function cleanup_deployment() {
  section "Cleaning up Percona MongoDB deployment"
  
  if ask_approval "Do you want to remove the complete Percona MongoDB deployment?"; then
    echo -e "${YELLOW}Removing MongoDB cluster...${NC}"
    kubectl delete psmdb -n pgo psmdb 2>/dev/null || true
    
    echo -e "${YELLOW}Removing MongoDB namespace...${NC}"
    kubectl delete namespace pgo --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}Removing PMM Server...${NC}"
    kubectl delete namespace monitoring --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}Removing Percona operator...${NC}"
    kubectl delete -f percona-server-mongodb-operator/deploy/operator.yaml 2>/dev/null || true
    kubectl delete -f percona-server-mongodb-operator/deploy/rbac.yaml 2>/dev/null || true
    kubectl delete -f percona-server-mongodb-operator/deploy/crd.yaml 2>/dev/null || true
    
    if ask_approval "Do you want to remove network components (MetalLB, cert-manager)?"; then
      echo -e "${YELLOW}Removing MetalLB...${NC}"
      kubectl delete namespace metallb-system --timeout=120s 2>/dev/null || true
      
      echo -e "${YELLOW}Removing cert-manager...${NC}"
      kubectl delete namespace cert-manager --timeout=120s 2>/dev/null || true
    fi
    
    echo -e "${GREEN}Cleanup completed${NC}"
  fi
}

# Main menu
function main_menu() {
  echo -e "${GREEN}Percona MongoDB Deployment Script${NC}"
  echo "=================================================="
  
  PS3='Select an option: '
  options=(
    "Deploy Complete Stack"
    "Install MongoDB Only"
    "Install PMM Server Only"
    "Setup Network Components Only"
    "Check Deployment Status"
    "Cleanup Deployment"
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Deploy Complete Stack")
        deploy_complete_stack
        ;;
      "Install MongoDB Only")
        install_mongodb_percona
        ;;
      "Install PMM Server Only")
        if declare -f install_pmm_server > /dev/null; then
          install_pmm_server
        else
          echo -e "${RED}PMM installation function not available${NC}"
        fi
        ;;
      "Setup Network Components Only")
        setup_network_components
        ;;
      "Check Deployment Status")
        section "Current Deployment Status"
        kubectl get psmdb -n pgo 2>/dev/null || echo "No MongoDB clusters"
        kubectl get pods -n pgo 2>/dev/null || echo "No MongoDB pods"
        kubectl get pods -n monitoring -l app=pmm-server 2>/dev/null || echo "No PMM Server"
        ;;
      "Cleanup Deployment")
        cleanup_deployment
        ;;
      "Quit")
        break
        ;;
      *) 
        echo "Invalid option $REPLY"
        ;;
    esac
  done
}

# Run main menu if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_menu
fi 