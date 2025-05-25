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

# Function to diagnose Grafana issues
function diagnose_grafana() {
  section "Grafana Diagnosis"
  
  echo -e "${YELLOW}Checking Grafana deployment...${NC}"
  
  # Check if Grafana namespace exists
  if kubectl get namespace monitoring &>/dev/null; then
    echo -e "${GREEN}✓ Monitoring namespace exists${NC}"
  else
    echo -e "${RED}✗ Monitoring namespace not found${NC}"
    echo -e "${YELLOW}Run './monitoring.sh' to install monitoring stack${NC}"
    return 1
  fi
  
  # Check for Grafana deployment
  GRAFANA_DEPLOY=$(kubectl get deployment -n monitoring | grep grafana | head -1 | awk '{print $1}' || echo "")
  if [[ -n "$GRAFANA_DEPLOY" ]]; then
    echo -e "${GREEN}✓ Grafana deployment found: $GRAFANA_DEPLOY${NC}"
    
    # Check deployment status
    kubectl get deployment "$GRAFANA_DEPLOY" -n monitoring
    
    # Check pods
    echo -e "\n${YELLOW}Grafana pods:${NC}"
    kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o wide
    
    # Check if pods are running
    RUNNING_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep Running | wc -l)
    if [[ $RUNNING_PODS -gt 0 ]]; then
      echo -e "${GREEN}✓ Grafana pods are running${NC}"
    else
      echo -e "${RED}✗ No Grafana pods are running${NC}"
      
      # Check pod logs
      echo -e "\n${YELLOW}Checking Grafana pod logs:${NC}"
      GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | head -1 | awk '{print $1}')
      if [[ -n "$GRAFANA_POD" ]]; then
        kubectl logs "$GRAFANA_POD" -n monitoring --tail=20
      fi
    fi
  else
    echo -e "${RED}✗ Grafana deployment not found${NC}"
    echo -e "${YELLOW}Checking for any Grafana-related resources:${NC}"
    kubectl get all -n monitoring | grep -i grafana || echo "No Grafana resources found"
    return 1
  fi
  
  # Check Grafana service
  echo -e "\n${YELLOW}Checking Grafana service:${NC}"
  GRAFANA_SVC=$(kubectl get svc -n monitoring | grep grafana | head -1 | awk '{print $1}' || echo "")
  if [[ -n "$GRAFANA_SVC" ]]; then
    echo -e "${GREEN}✓ Grafana service found: $GRAFANA_SVC${NC}"
    kubectl get svc "$GRAFANA_SVC" -n monitoring
    
    # Check service endpoints
    echo -e "\n${YELLOW}Service endpoints:${NC}"
    kubectl get endpoints "$GRAFANA_SVC" -n monitoring
  else
    echo -e "${RED}✗ Grafana service not found${NC}"
  fi
  
  # Check ingress
  echo -e "\n${YELLOW}Checking Grafana ingress:${NC}"
  GRAFANA_INGRESS=$(kubectl get ingress -n monitoring | grep grafana | head -1 | awk '{print $1}' || echo "")
  if [[ -n "$GRAFANA_INGRESS" ]]; then
    echo -e "${GREEN}✓ Grafana ingress found: $GRAFANA_INGRESS${NC}"
    kubectl get ingress "$GRAFANA_INGRESS" -n monitoring
    kubectl describe ingress "$GRAFANA_INGRESS" -n monitoring
  else
    echo -e "${YELLOW}✗ No Grafana ingress found${NC}"
    echo -e "${YELLOW}Grafana may only be accessible via port-forward${NC}"
  fi
  
  # Test port-forward connectivity
  echo -e "\n${YELLOW}Testing port-forward connectivity:${NC}"
  if [[ -n "$GRAFANA_SVC" ]]; then
    echo -e "${YELLOW}To access Grafana, run:${NC}"
    echo "kubectl port-forward svc/$GRAFANA_SVC 3000:80 -n monitoring"
    echo -e "${YELLOW}Then visit: http://localhost:3000${NC}"
  fi
}

# Function to fix Grafana issues
function fix_grafana_issues() {
  section "Fixing Grafana Issues"
  
  if ask_approval "Do you want to attempt to fix Grafana issues?"; then
    echo -e "${YELLOW}Checking Grafana deployment status...${NC}"
    
    # Check if monitoring namespace exists
    if ! kubectl get namespace monitoring &>/dev/null; then
      echo -e "${RED}Monitoring namespace not found${NC}"
      if ask_approval "Do you want to install the monitoring stack?"; then
        if [[ -f "./monitoring.sh" ]]; then
          echo -e "${YELLOW}Running monitoring.sh...${NC}"
          ./monitoring.sh
        else
          echo -e "${RED}monitoring.sh not found${NC}"
        fi
      fi
      return
    fi
    
    # Check for failed Grafana pods
    FAILED_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers | grep -v Running | awk '{print $1}')
    if [[ -n "$FAILED_PODS" ]]; then
      echo -e "${YELLOW}Found failed Grafana pods: $FAILED_PODS${NC}"
      if ask_approval "Do you want to restart failed Grafana pods?"; then
        for pod in $FAILED_PODS; do
          echo -e "${YELLOW}Deleting pod: $pod${NC}"
          kubectl delete pod "$pod" -n monitoring
        done
        echo -e "${GREEN}Pods deleted. Waiting for restart...${NC}"
        sleep 10
      fi
    fi
    
    # Check if Grafana deployment exists
    GRAFANA_DEPLOY=$(kubectl get deployment -n monitoring | grep grafana | head -1 | awk '{print $1}' || echo "")
    if [[ -z "$GRAFANA_DEPLOY" ]]; then
      echo -e "${RED}No Grafana deployment found${NC}"
      if ask_approval "Do you want to reinstall the monitoring stack?"; then
        if [[ -f "./monitoring.sh" ]]; then
          echo -e "${YELLOW}Running monitoring.sh...${NC}"
          ./monitoring.sh
        else
          echo -e "${RED}monitoring.sh not found${NC}"
        fi
      fi
      return
    fi
    
    # Scale deployment if needed
    REPLICAS=$(kubectl get deployment "$GRAFANA_DEPLOY" -n monitoring -o jsonpath='{.spec.replicas}')
    READY_REPLICAS=$(kubectl get deployment "$GRAFANA_DEPLOY" -n monitoring -o jsonpath='{.status.readyReplicas}' || echo "0")
    
    if [[ "$READY_REPLICAS" != "$REPLICAS" ]]; then
      echo -e "${YELLOW}Grafana deployment not fully ready ($READY_REPLICAS/$REPLICAS)${NC}"
      if ask_approval "Do you want to restart the Grafana deployment?"; then
        kubectl rollout restart deployment "$GRAFANA_DEPLOY" -n monitoring
        echo -e "${YELLOW}Waiting for rollout to complete...${NC}"
        kubectl rollout status deployment "$GRAFANA_DEPLOY" -n monitoring --timeout=300s
      fi
    fi
    
    # Check persistent volumes
    echo -e "\n${YELLOW}Checking Grafana persistent volumes...${NC}"
    kubectl get pvc -n monitoring | grep grafana || echo "No Grafana PVCs found"
    
    # Provide access instructions
    echo -e "\n${GREEN}Grafana Access Instructions:${NC}"
    GRAFANA_SVC=$(kubectl get svc -n monitoring | grep grafana | head -1 | awk '{print $1}' || echo "")
    if [[ -n "$GRAFANA_SVC" ]]; then
      echo "1. Port-forward: kubectl port-forward svc/$GRAFANA_SVC 3000:80 -n monitoring"
      echo "2. Visit: http://localhost:3000"
      echo "3. Default credentials: admin/admin (change on first login)"
    fi
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
    
    echo "=== Grafana Status ==="
    kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null || echo "No Grafana pods found"
    kubectl get svc -n monitoring | grep grafana || echo "No Grafana service found"
    kubectl get ingress -n monitoring | grep grafana || echo "No Grafana ingress found"
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
    "Diagnose Grafana Issues"
    "Fix Grafana Issues"
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
      "Diagnose Grafana Issues")
        diagnose_grafana
        ;;
      "Fix Grafana Issues")
        fix_grafana_issues
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
        diagnose_grafana
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