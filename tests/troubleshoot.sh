#!/bin/bash

# Troubleshooting Script for Wity Cloud Deploy
# Helps diagnose and fix common deployment issues

# Source common functions
if [[ -f "./common.sh" ]]; then
  source "./common.sh"
else
  echo "common.sh not found. This script requires common functions."
  exit 1
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

# Function to check system health
function check_system_health() {
  section "System Health Check"
  
  echo -e "${YELLOW}Checking system resources...${NC}"
  
  # Check memory
  MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
  MEMORY_USED=$(free -g | awk '/^Mem:/{print $3}')
  echo -e "${GREEN}Memory: ${MEMORY_USED}GB used / ${MEMORY_GB}GB total${NC}"
  
  if [[ $MEMORY_GB -lt 4 ]]; then
    echo -e "${YELLOW}Warning: Less than 4GB RAM available${NC}"
  fi
  
  # Check disk space
  DISK_USAGE=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
  echo -e "${GREEN}Disk usage: ${DISK_USAGE}%${NC}"
  
  if [[ $DISK_USAGE -gt 80 ]]; then
    echo -e "${YELLOW}Warning: Disk usage is above 80%${NC}"
  fi
  
  # Check file limits
  echo -e "${GREEN}Current file limits:${NC}"
  echo "  Soft limit: $(ulimit -Sn)"
  echo "  Hard limit: $(ulimit -Hn)"
  
  # Check if RKE2 is running
  if systemctl is-active --quiet rke2-server; then
    echo -e "${GREEN}✓ RKE2 server is running${NC}"
  else
    echo -e "${RED}✗ RKE2 server is not running${NC}"
  fi
  
  # Check kubectl connectivity
  if kubectl get nodes &>/dev/null; then
    echo -e "${GREEN}✓ kubectl can connect to cluster${NC}"
    kubectl get nodes
  else
    echo -e "${RED}✗ kubectl cannot connect to cluster${NC}"
  fi
}

# Function to diagnose Cilium issues
function diagnose_cilium() {
  section "Cilium Diagnosis"
  
  echo -e "${YELLOW}Checking Cilium installations...${NC}"
  
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
  
  # Check for conflicting resources
  echo -e "\n${YELLOW}Checking for conflicting resources...${NC}"
  
  if kubectl get serviceaccount cilium -n kube-system &>/dev/null; then
    OWNER=$(kubectl get serviceaccount cilium -n kube-system -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}Cilium ServiceAccount found, owned by: $OWNER${NC}"
    
    if [[ "$OWNER" == "rke2-cilium" ]]; then
      echo -e "${GREEN}ServiceAccount properly owned by RKE2${NC}"
    elif [[ "$OWNER" == "cilium" ]]; then
      echo -e "${GREEN}ServiceAccount properly owned by Helm${NC}"
    else
      echo -e "${RED}ServiceAccount has conflicting ownership${NC}"
    fi
  else
    echo -e "${YELLOW}No Cilium ServiceAccount found${NC}"
  fi
}

# Function to fix Cilium conflicts
function fix_cilium_conflicts() {
  section "Fixing Cilium Conflicts"
  
  if ask_approval "Do you want to attempt to fix Cilium conflicts?"; then
    echo -e "${YELLOW}Checking for conflicts...${NC}"
    
    # Check if both RKE2 and Helm Cilium exist
    RKE2_CILIUM=$(helm list -n kube-system | grep -c "rke2-cilium" || echo "0")
    HELM_CILIUM=$(helm list -n kube-system | grep -c "^cilium" || echo "0")
    
    if [[ $RKE2_CILIUM -gt 0 && $HELM_CILIUM -gt 0 ]]; then
      echo -e "${RED}Conflict detected: Both RKE2 and Helm Cilium installations found${NC}"
      
      if ask_approval "Do you want to remove the Helm Cilium installation and keep RKE2's?"; then
        echo -e "${YELLOW}Removing Helm Cilium installation...${NC}"
        helm uninstall cilium -n kube-system || true
        sleep 10
        echo -e "${GREEN}Helm Cilium removed. RKE2's Cilium should now work properly.${NC}"
      fi
    elif [[ $RKE2_CILIUM -gt 0 ]]; then
      echo -e "${GREEN}Only RKE2's Cilium found - this is the expected state${NC}"
    elif [[ $HELM_CILIUM -gt 0 ]]; then
      echo -e "${GREEN}Only Helm Cilium found - this should work fine${NC}"
    else
      echo -e "${RED}No Cilium installation found - this is a problem${NC}"
      
      if ask_approval "Do you want to install Cilium via Helm?"; then
        # Source core.sh to get install_cilium function
        if [[ -f "./core.sh" ]]; then
          source "./core.sh"
          install_cilium
        else
          echo -e "${RED}core.sh not found - cannot install Cilium${NC}"
        fi
      fi
    fi
  fi
}

# Function to check and fix common issues
function check_common_issues() {
  section "Checking Common Issues"
  
  echo -e "${YELLOW}1. Checking file limits...${NC}"
  SOFT_LIMIT=$(ulimit -Sn)
  if [[ $SOFT_LIMIT -lt 65536 ]]; then
    echo -e "${YELLOW}File limit is low ($SOFT_LIMIT). Recommended: 65536+${NC}"
    
    if ask_approval "Do you want to increase file limits?"; then
      cat > /etc/security/limits.d/99-kubernetes.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
      echo -e "${GREEN}File limits configuration updated. Please log out and back in.${NC}"
    fi
  else
    echo -e "${GREEN}File limits are adequate ($SOFT_LIMIT)${NC}"
  fi
  
  echo -e "\n${YELLOW}2. Checking system parameters...${NC}"
  if [[ ! -f /etc/sysctl.d/99-kubernetes.conf ]]; then
    echo -e "${YELLOW}Kubernetes system parameters not configured${NC}"
    
    if ask_approval "Do you want to apply recommended system parameters?"; then
      cat > /etc/sysctl.d/99-kubernetes.conf << EOF
fs.inotify.max_user_watches=524288
fs.file-max=131072
vm.max_map_count=262144
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
EOF
      sysctl --system
      echo -e "${GREEN}System parameters applied${NC}"
    fi
  else
    echo -e "${GREEN}System parameters are configured${NC}"
  fi
  
  echo -e "\n${YELLOW}3. Checking for stuck namespaces...${NC}"
  STUCK_NS=$(kubectl get namespaces | grep Terminating | awk '{print $1}' || echo "")
  if [[ -n "$STUCK_NS" ]]; then
    echo -e "${YELLOW}Found stuck namespaces: $STUCK_NS${NC}"
    
    if ask_approval "Do you want to force delete stuck namespaces?"; then
      for ns in $STUCK_NS; do
        echo -e "${YELLOW}Force deleting namespace: $ns${NC}"
        kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge || true
      done
    fi
  else
    echo -e "${GREEN}No stuck namespaces found${NC}"
  fi
}

# Function to collect system information
function collect_system_info() {
  section "Collecting System Information"
  
  local info_file="/tmp/wity-deploy-info-$(date +%Y%m%d-%H%M%S).txt"
  
  echo -e "${YELLOW}Collecting system information to: $info_file${NC}"
  
  {
    echo "=== Wity Cloud Deploy System Information ==="
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo ""
    
    echo "=== System Resources ==="
    echo "Memory:"
    free -h
    echo ""
    echo "Disk Usage:"
    df -h
    echo ""
    echo "CPU Info:"
    lscpu | grep -E "Model name|CPU\(s\)|Thread"
    echo ""
    
    echo "=== File Limits ==="
    echo "Current limits:"
    ulimit -a
    echo ""
    
    echo "=== RKE2 Status ==="
    systemctl status rke2-server --no-pager -l || echo "RKE2 server not running"
    echo ""
    
    echo "=== Kubernetes Nodes ==="
    kubectl get nodes -o wide 2>/dev/null || echo "Cannot connect to cluster"
    echo ""
    
    echo "=== Kubernetes Pods ==="
    kubectl get pods --all-namespaces 2>/dev/null || echo "Cannot connect to cluster"
    echo ""
    
    echo "=== Helm Releases ==="
    helm list --all-namespaces 2>/dev/null || echo "Helm not available or no releases"
    echo ""
    
    echo "=== Cilium Status ==="
    helm list -n kube-system | grep cilium || echo "No Cilium releases found"
    kubectl get pods -n kube-system -l k8s-app=cilium 2>/dev/null || echo "No Cilium pods found"
    echo ""
    
    echo "=== Recent RKE2 Logs ==="
    journalctl -u rke2-server --no-pager -l | tail -50 || echo "No RKE2 logs available"
    
  } > "$info_file"
  
  echo -e "${GREEN}System information collected in: $info_file${NC}"
  echo -e "${YELLOW}You can share this file for troubleshooting support${NC}"
}

# Main menu
function main_menu() {
  echo -e "${GREEN}Wity Cloud Deploy - Troubleshooting Tool${NC}"
  echo "=================================================="
  
  PS3='Select troubleshooting option: '
  options=(
    "System Health Check"
    "Diagnose Cilium Issues"
    "Fix Cilium Conflicts"
    "Check Common Issues"
    "Collect System Information"
    "Full Diagnostic Run"
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "System Health Check")
        check_system_health
        ;;
      "Diagnose Cilium Issues")
        diagnose_cilium
        ;;
      "Fix Cilium Conflicts")
        fix_cilium_conflicts
        ;;
      "Check Common Issues")
        check_common_issues
        ;;
      "Collect System Information")
        collect_system_info
        ;;
      "Full Diagnostic Run")
        check_system_health
        diagnose_cilium
        check_common_issues
        collect_system_info
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