#!/bin/bash

set -e

# Source the common functions
if [[ -f "./common.sh" ]]; then
  source "./common.sh"
else
  echo "common.sh not found. This script requires common functions."
  exit 1
fi

# Source environment setup if available, create it if not
if [[ -f "/root/setup-k8s-env.sh" ]]; then
  echo -e "${GREEN}Loading RKE2 environment...${NC}"
  source "/root/setup-k8s-env.sh"
else
  # Create the environment setup script if it doesn't exist
  echo -e "${YELLOW}Creating RKE2 environment setup script...${NC}"
  create_setup_script
  if [[ -f "/root/setup-k8s-env.sh" ]]; then
    source "/root/setup-k8s-env.sh"
  fi
fi

# Source component scripts
component_scripts=(
  "./core.sh"
  "./storage.sh"
  "./monitoring.sh"
  "./management.sh"
  "./databases.sh"
  "./aws.sh"
  "./utilities.sh"
  "./cluster.sh"
)

for script in "${component_scripts[@]}"; do
  if [[ -f "$script" ]]; then
    source "$script"
  else
    echo "Warning: $script not found. Some functionality may be limited."
  fi
done

# Initialize variables
NODE_IP=$(get_node_ip)

# Check if script is being run as root
check_root

# Comprehensive installation function
function install_all_essentials() {
  section "Installing All Essential Components"
  
  echo -e "${YELLOW}This will install a complete Kubernetes platform with:${NC}"
  echo -e "  - RKE2 Server (if not already installed)"
  echo -e "  - Helm package manager"
  echo -e "  - Cilium CNI (if not already installed)"
  echo -e "  - MetalLB load balancer"
  echo -e "  - Longhorn storage"
  echo -e "  - Prometheus + Grafana monitoring"
  echo -e "  - Loki log aggregation"
  echo -e "  - Cert Manager for TLS"
  echo -e "  - Rancher management UI"
  echo -e "  - Traefik ingress controller"
  echo -e "  - PostgreSQL database"
  echo -e "  - pgAdmin database management"
  echo ""
  
  read -p "Do you want to proceed? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    return
  fi
  
  # Enable batch mode for automatic handling of existing installations
  export BATCH_MODE=true
  
  echo -e "${GREEN}Starting comprehensive installation...${NC}"
  echo -e "${YELLOW}Note: Existing installations will be automatically handled${NC}"
  
  # Core components
  echo -e "\n${YELLOW}=== PHASE 1: Core Infrastructure ===${NC}"
  
  # Check if RKE2 is already running
  if ! systemctl is-active --quiet rke2-server 2>/dev/null; then
    install_rke2_server
    sleep 30  # Wait for RKE2 to be ready
  else
    echo -e "${GREEN}RKE2 server already running${NC}"
  fi
  
  # Ensure kubectl access
  setup_path
  export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  
  # Wait for cluster to be ready
  echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
  timeout 300 bash -c 'until kubectl get nodes | grep -q Ready; do sleep 5; done' || {
    echo -e "${RED}Cluster failed to become ready${NC}"
    return 1
  }
  
  install_helm
  add_helm_repos
  
  # Only install Cilium if not already installed by RKE2
  if ! helm list -n kube-system | grep -q cilium; then
    install_cilium
  else
    echo -e "${GREEN}Cilium already installed by RKE2${NC}"
  fi
  
  install_metallb
  
  # Storage
  echo -e "\n${YELLOW}=== PHASE 2: Storage ===${NC}"
  install_longhorn
  
  # Wait for Longhorn to be ready
  echo -e "${YELLOW}Waiting for Longhorn to be ready...${NC}"
  kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s
  
  # Management
  echo -e "\n${YELLOW}=== PHASE 3: Management Tools ===${NC}"
  install_cert_manager
  install_traefik_ingress
  
  # Wait for cert-manager to be ready
  echo -e "${YELLOW}Waiting for cert-manager to be ready...${NC}"
  kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
  
  install_rancher
  
  # Monitoring
  echo -e "\n${YELLOW}=== PHASE 4: Monitoring & Logging ===${NC}"
  install_monitoring
  install_loki
  
  # Database
  echo -e "\n${YELLOW}=== PHASE 5: Database Services ===${NC}"
  install_postgres_bitnami
  install_pgadmin
  
  # Setup ingresses
  echo -e "\n${YELLOW}=== PHASE 6: Ingress Configuration ===${NC}"
  setup_grafana_ingress
  setup_prometheus_ingress
  
  # Final status
  echo -e "\n${GREEN}=== INSTALLATION COMPLETE ===${NC}"
  show_cluster_status_summary
  
  echo -e "\n${GREEN}Essential services installed successfully!${NC}"
  echo -e "${YELLOW}Access URLs:${NC}"
  echo -e "  Rancher:    https://rancher.${NODE_IP}.nip.io"
  echo -e "  Grafana:    http://grafana.${NODE_IP}.nip.io"
  echo -e "  Prometheus: http://prometheus.${NODE_IP}.nip.io"
  echo -e "  pgAdmin:    http://pgadmin.${NODE_IP}.nip.io"
  echo -e "\n${YELLOW}Default credentials:${NC}"
  echo -e "  Grafana: admin/prom-operator"
  echo -e "  pgAdmin: admin@admin.com/admin"
  echo -e "  PostgreSQL: postgres/secretpassword"
  
  # Disable batch mode
  export BATCH_MODE=false
}

# Main menu function
function show_main_menu() {
  clear
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${GREEN}               Wity Cloud Deploy Tool                    ${NC}"
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${YELLOW}Node IP: ${NODE_IP}${NC}"
  
  # Check if RKE2 is running
  if systemctl is-active --quiet rke2-server 2>/dev/null; then
    echo -e "${GREEN}RKE2 Server Status: Running${NC}"
  elif systemctl is-active --quiet rke2-agent 2>/dev/null; then
    echo -e "${GREEN}RKE2 Agent Status: Running${NC}"
  else
    echo -e "${YELLOW}RKE2 Status: Not running${NC}"
  fi
  
  # Check kubectl status
  if command -v kubectl &> /dev/null; then
    if kubectl get nodes &> /dev/null 2>&1; then
      echo -e "${GREEN}kubectl Status: Working properly${NC}"
    else
      echo -e "${YELLOW}kubectl Status: Found but cannot access cluster${NC}"
    fi
  else
    echo -e "${YELLOW}kubectl Status: Not found in PATH${NC}"
  fi
  
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${YELLOW}Select a category to proceed:${NC}"
  echo ""
}

# Function to show component menu with manual options
function show_component_menu() {
  local title=$1
  local category=$2
  
  clear
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${GREEN}               $title                                    ${NC}"
  echo -e "${GREEN}=========================================================${NC}"
  
  case $category in
    "core")
      options=("RKE2 Server" "RKE2 Agent" "Helm + Repos" "Cilium" "MetalLB" "All Core Components" "Back to Main Menu")
      ;;
    "storage")
      options=("Longhorn" "Back to Main Menu")
      ;;
    "monitoring")
      options=("Prometheus + Grafana" "Loki + Promtail" "Setup Grafana Ingress" "Setup Prometheus Ingress" "Check Status" "All Monitoring Components" "Back to Main Menu")
      ;;
    "management")
      options=("Cert Manager" "Rancher" "Traefik Ingress" "pgAdmin" "All Management Components" "Back to Main Menu")
      ;;
    "databases")
      options=("MongoDB (Percona)" "PostgreSQL" "MySQL" "Redis" "MariaDB" "All Databases" "Back to Main Menu")
      ;;
    "aws")
      options=("AWS CLI Setup" "S3 Bucket for Velero" "Push to ECR" "Configure Domain" "Route53 Record" "Setup All Route53 Records" "Back to Main Menu")
      ;;
    "cluster")
      options=("Show Cluster Info" "Get Join Token" "Prepare Join Script" "Install KubeVirt" "Create Cluster Backup" "Back to Main Menu")
      ;;
    "utilities")
      options=("Request TLS Certificates" "Patch Ingresses for TLS" "Show Status Summary" "Check Node Taints" "Check Deployment Status" "Service Health Check" "Debug Namespace" "View Pod Logs" "Uninstall Components" "Back to Main Menu")
      ;;
  esac
  
  select opt in "${options[@]}"; do
    case $category in
      "core")
        case $opt in
          "RKE2 Server") install_rke2_server ;;
          "RKE2 Agent") install_rke2_agent ;;
          "Helm + Repos") install_helm; add_helm_repos ;;
          "Cilium") install_cilium ;;
          "MetalLB") install_metallb ;;
          "All Core Components") 
            install_rke2_server
            install_helm
            add_helm_repos
            install_cilium
            install_metallb
            ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "storage")
        case $opt in
          "Longhorn") install_longhorn ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "monitoring")
        case $opt in
          "Prometheus + Grafana") install_monitoring ;;
          "Loki + Promtail") install_loki ;;
          "Setup Grafana Ingress") setup_grafana_ingress ;;
          "Setup Prometheus Ingress") setup_prometheus_ingress ;;
          "Check Status") check_monitoring_status ;;
          "All Monitoring Components") 
            install_monitoring
            install_loki
            setup_grafana_ingress
            setup_prometheus_ingress
            ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "management")
        case $opt in
          "Cert Manager") install_cert_manager ;;
          "Rancher") install_rancher ;;
          "Traefik Ingress") install_traefik_ingress ;;
          "pgAdmin") install_pgadmin ;;
          "All Management Components") 
            install_cert_manager
            install_rancher
            install_traefik_ingress
            install_pgadmin
            ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "databases")
        case $opt in
          "MongoDB (Percona)") install_mongodb_percona ;;
          "PostgreSQL") install_postgres_bitnami ;;
          "MySQL") install_mysql_bitnami ;;
          "Redis") install_redis_bitnami ;;
          "MariaDB") install_mariadb_bitnami ;;
          "All Databases") 
            install_mongodb_percona
            install_postgres_bitnami
            install_mysql_bitnami
            install_redis_bitnami
            install_mariadb_bitnami
            ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "aws")
        case $opt in
          "AWS CLI Setup") setup_aws_cli ;;
          "S3 Bucket for Velero") create_s3_bucket_for_velero ;;
          "Push to ECR") push_sample_image_to_ecr ;;
          "Configure Domain") configure_base_domain ;;
          "Route53 Record") setup_route53_record ;;
          "Setup All Route53 Records") setup_all_route53_records ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "cluster")
        case $opt in
          "Show Cluster Info") show_cluster_info ;;
          "Get Join Token") get_rke2_token ;;
          "Prepare Join Script") prepare_join_script ;;
          "Install KubeVirt") install_kubevirt ;;
          "Create Cluster Backup") create_backup ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      "utilities")
        case $opt in
          "Request TLS Certificates") apply_tls_certificates ;;
          "Patch Ingresses for TLS") patch_ingresses_for_tls ;;
          "Show Status Summary") show_cluster_status_summary ;;
          "Check Node Taints") check_node_taints_and_labels ;;
          "Check Deployment Status") wait_for_deployments ;;
          "Service Health Check") check_service_health_detailed ;;
          "Debug Namespace") debug_namespace ;;
          "View Pod Logs") debug_pod_logs ;;
          "Uninstall Components") uninstall_component ;;
          "Back to Main Menu") break ;;
          *) echo "Invalid option" ;;
        esac
        ;;
    esac
    
    if [[ "$opt" != "Back to Main Menu" ]]; then
      echo -e "\n${GREEN}Operation completed. Press Enter to continue...${NC}"
      read
    fi
  done
}

# Main menu options
PS3='Enter your choice (1-10): '
options=(
  "🚀 Install All Essentials (Recommended)"
  "Core Components (RKE2, Helm, Cilium, MetalLB)"
  "Storage (Longhorn)"
  "Monitoring (Prometheus, Grafana, Loki)"
  "Management (Rancher, Cert Manager, Traefik, pgAdmin)"
  "Databases (MongoDB, PostgreSQL, MySQL, Redis, MariaDB)"
  "AWS Integration (S3, ECR, Route53)"
  "Cluster Management (Join, Info, Backup)"
  "Utilities (Status, TLS, Debugging)"
  "Quit"
)

# Main loop
while true; do
  show_main_menu
  select opt in "${options[@]}"; do
    case $opt in
      "🚀 Install All Essentials (Recommended)")
        install_all_essentials
        break
        ;;
      "Core Components (RKE2, Helm, Cilium, MetalLB)")
        show_component_menu "Core Components" "core"
        break
        ;;
      "Storage (Longhorn)")
        show_component_menu "Storage" "storage"
        break
        ;;
      "Monitoring (Prometheus, Grafana, Loki)")
        show_component_menu "Monitoring" "monitoring"
        break
        ;;
      "Management (Rancher, Cert Manager, Traefik, pgAdmin)")
        show_component_menu "Management" "management"
        break
        ;;
      "Databases (MongoDB, PostgreSQL, MySQL, Redis, MariaDB)")
        show_component_menu "Databases" "databases"
        break
        ;;
      "AWS Integration (S3, ECR, Route53)")
        show_component_menu "AWS Integration" "aws"
        break
        ;;
      "Cluster Management (Join, Info, Backup)")
        show_component_menu "Cluster Management" "cluster"
        break
        ;;
      "Utilities (Status, TLS, Debugging)")
        show_component_menu "Utilities" "utilities"
        break
        ;;
      "Quit")
        echo "Goodbye!"
        exit 0
        ;;
      *)
        echo "Invalid option"
        ;;
    esac
  done
done
