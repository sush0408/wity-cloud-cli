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

function get_rke2_token() {
  section "Retrieving RKE2 Token"
  
  if [[ -f /var/lib/rancher/rke2/server/node-token ]]; then
    NODE_TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)
    NODE_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}Your RKE2 server is at: ${NODE_IP}${NC}"
    echo -e "${GREEN}Your RKE2 token is: ${NODE_TOKEN}${NC}"
    echo -e "\n${YELLOW}To join another node to this cluster, run the following:${NC}"
    echo -e "mkdir -p /etc/rancher/rke2"
    echo -e "cat <<EOF > /etc/rancher/rke2/config.yaml"
    echo -e "server: https://${NODE_IP}:9345"
    echo -e "token: ${NODE_TOKEN}"
    echo -e "EOF"
    echo -e "curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=\"agent\" sh -"
    echo -e "systemctl enable rke2-agent.service"
    echo -e "systemctl start rke2-agent.service"
  else
    echo -e "${YELLOW}No RKE2 server token found. Is RKE2 server installed on this node?${NC}"
  fi
}

function prepare_join_script() {
  section "Creating Join Script for Worker Nodes"
  
  if [[ -f /var/lib/rancher/rke2/server/node-token ]]; then
    NODE_TOKEN=$(cat /var/lib/rancher/rke2/server/node-token)
    NODE_IP=$(hostname -I | awk '{print $1}')
    
    cat <<EOF > join-cluster.sh
#!/bin/bash

# Script to join an RKE2 cluster as an agent (worker) node
# Generated on: $(date)
# Server: ${NODE_IP}

set -e

echo "Installing RKE2 agent and joining cluster at ${NODE_IP}..."

# Create RKE2 configuration
mkdir -p /etc/rancher/rke2
cat <<CONFIG > /etc/rancher/rke2/config.yaml
server: https://${NODE_IP}:9345
token: ${NODE_TOKEN}
CONFIG

# Install RKE2 agent
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -

# Enable and start service
systemctl enable rke2-agent.service
systemctl start rke2-agent.service

echo "Node joined the cluster. Check the status on the server with:"
echo "kubectl get nodes"
EOF
    
    chmod +x join-cluster.sh
    echo -e "${GREEN}Join script created: join-cluster.sh${NC}"
    echo -e "${YELLOW}Copy this script to worker nodes and execute it to join the cluster.${NC}"
  else
    echo -e "${YELLOW}No RKE2 server token found. Is RKE2 server installed on this node?${NC}"
  fi
}

function install_kubevirt() {
  section "Installing KubeVirt"
  export KUBEVIRT_VERSION=$(curl -s https://api.github.com/repos/kubevirt/kubevirt/releases/latest | grep tag_name | cut -d '"' -f 4)
  kubectl create namespace kubevirt || true
  kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml
  kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml
  echo -e "${GREEN}KubeVirt installed. It may take a few minutes for the VM functionality to become ready.${NC}"
}

function show_cluster_info() {
  section "Cluster Information"
  
  echo -e "${YELLOW}Node Information:${NC}"
  kubectl get nodes -o wide
  
  echo -e "\n${YELLOW}Kubernetes Version:${NC}"
  kubectl version --short
  
  echo -e "\n${YELLOW}Node Resources:${NC}"
  kubectl top nodes 2>/dev/null || echo -e "${YELLOW}Metrics server not available${NC}"
  
  echo -e "\n${YELLOW}Storage Classes:${NC}"
  kubectl get sc
  
  echo -e "\n${YELLOW}Namespaces:${NC}"
  kubectl get ns
  
  echo -e "\n${YELLOW}API Resources:${NC}"
  kubectl api-resources --namespaced=false | head -n 20
  echo -e "${YELLOW}... and more (truncated)${NC}"
}

function create_backup() {
  section "Creating Cluster Backup"
  
  backup_dir="/root/cluster-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  
  # Get cluster resources
  echo -e "${YELLOW}Backing up cluster resources to $backup_dir${NC}"
  
  # Namespaces
  kubectl get namespaces -o yaml > "$backup_dir/namespaces.yaml"
  
  # For each namespace, backup key resources
  namespaces=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
  for ns in $namespaces; do
    ns_dir="$backup_dir/$ns"
    mkdir -p "$ns_dir"
    
    echo -e "${YELLOW}Backing up resources in namespace: $ns${NC}"
    
    # Skip some system namespaces for certain resources to avoid huge files
    if [[ "$ns" != "kube-system" && "$ns" != "kube-public" && "$ns" != "kube-node-lease" ]]; then
      kubectl get deploy,sts,ds,cm,secret,svc,ing,pvc -n "$ns" -o yaml > "$ns_dir/resources.yaml"
    else
      # For system namespaces, only get specific resources
      kubectl get deploy,sts,ds,svc -n "$ns" -o yaml > "$ns_dir/resources.yaml"
    fi
  done
  
  # Get etcd backup if available on RKE2
  if [[ -d /var/lib/rancher/rke2/server/db/snapshots ]]; then
    mkdir -p "$backup_dir/etcd"
    cp -r /var/lib/rancher/rke2/server/db/snapshots/* "$backup_dir/etcd/" 2>/dev/null || echo "No etcd snapshots found"
  fi
  
  # Get RKE2 configuration
  if [[ -d /etc/rancher/rke2 ]]; then
    mkdir -p "$backup_dir/rke2-config"
    cp -r /etc/rancher/rke2/* "$backup_dir/rke2-config/" 2>/dev/null
  fi
  
  # Create archive
  archive_file="/root/cluster-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$archive_file" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
  
  # Cleanup
  rm -rf "$backup_dir"
  
  echo -e "${GREEN}Backup completed: $archive_file${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Cluster Management script directly"
  PS3='Select cluster operation: '
  options=(
    "Show Cluster Info" 
    "Get Join Token" 
    "Prepare Join Script"
    "Install KubeVirt"
    "Create Cluster Backup" 
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Show Cluster Info")
        show_cluster_info
        ;;
      "Get Join Token")
        get_rke2_token
        ;;
      "Prepare Join Script")
        prepare_join_script
        ;;
      "Install KubeVirt")
        install_kubevirt
        ;;
      "Create Cluster Backup")
        create_backup
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