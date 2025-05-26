#!/bin/bash

# Main deployment orchestration script
# This script coordinates the deployment of the complete infrastructure stack

# Source common functions
  source "./common.sh"

# Global configuration
BATCH_MODE=${BATCH_MODE:-false}
SKIP_CONFIRMATIONS=${SKIP_CONFIRMATIONS:-false}

function show_banner() {
  echo -e "${GREEN}"
  echo "=================================================="
  echo "    Wity Cloud Deploy - Complete Infrastructure"
  echo "=================================================="
  echo -e "${NC}"
  echo "This script will deploy a complete cloud infrastructure including:"
  echo "• Kubernetes cluster (K3s)"
  echo "• MongoDB with Percona Operator (Sharded)"
  echo "• Redis cluster"
  echo "• Monitoring stack (Prometheus, Grafana, Loki)"
  echo "• PMM Server for database monitoring"
  echo "• ArgoCD for GitOps CI/CD"
  echo "• Ingress controllers and networking"
  echo ""
}

function check_prerequisites() {
  section "Checking Prerequisites"
  
  # Check if running as root
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
  exit 1
fi

  # Check system resources
  local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
  local total_cpu=$(nproc)
  local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
  
  echo -e "${YELLOW}System Resources:${NC}"
  echo "  Memory: ${total_memory}GB"
  echo "  CPU Cores: ${total_cpu}"
  echo "  Available Disk: ${available_disk}GB"
  
  # Minimum requirements check
  local min_memory=8
  local min_cpu=4
  local min_disk=50
  
  if [[ $total_memory -lt $min_memory ]]; then
    echo -e "${RED}⚠️  Warning: Minimum ${min_memory}GB RAM recommended${NC}"
  fi
  
  if [[ $total_cpu -lt $min_cpu ]]; then
    echo -e "${RED}⚠️  Warning: Minimum ${min_cpu} CPU cores recommended${NC}"
  fi
  
  if [[ $available_disk -lt $min_disk ]]; then
    echo -e "${RED}⚠️  Warning: Minimum ${min_disk}GB disk space recommended${NC}"
  fi
  
  # Check internet connectivity
  if ! ping -c 1 google.com &> /dev/null; then
    echo -e "${RED}❌ No internet connectivity detected${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}✅ Prerequisites check completed${NC}"
}

function deploy_infrastructure() {
  section "Deploying Infrastructure Components"
  
  # 1. Deploy Kubernetes cluster
  if ask_approval "Deploy K3s Kubernetes cluster?"; then
    echo -e "${YELLOW}[1/7] Deploying K3s...${NC}"
    source "./infrastructure.sh"
    install_k3s
    setup_metallb
    setup_cert_manager
  fi
  
  # 2. Deploy storage
  if ask_approval "Deploy Longhorn storage?"; then
    echo -e "${YELLOW}[2/7] Deploying Longhorn storage...${NC}"
    source "./infrastructure.sh"
    install_longhorn
  fi
  
  # 3. Deploy databases
  if ask_approval "Deploy database stack (MongoDB + Redis)?"; then
    echo -e "${YELLOW}[3/7] Deploying databases...${NC}"
    source "./databases.sh"
    install_mongodb_percona
    install_redis_bitnami
  fi
  
  # 4. Deploy monitoring
  if ask_approval "Deploy monitoring stack (Prometheus + Grafana + Loki)?"; then
    echo -e "${YELLOW}[4/7] Deploying monitoring...${NC}"
    source "./monitoring.sh"
    install_monitoring
    install_loki
    configure_loki_datasource
  fi
  
  # 5. Deploy PMM for database monitoring
  if ask_approval "Deploy PMM Server for database monitoring?"; then
    echo -e "${YELLOW}[5/7] Deploying PMM Server...${NC}"
    source "./databases.sh"
    install_pmm_server_for_mongodb
  fi
  
  # 6. Deploy CI/CD
  if ask_approval "Deploy ArgoCD for GitOps CI/CD?"; then
    echo -e "${YELLOW}[6/7] Deploying ArgoCD...${NC}"
    source "./cicd.sh"
    install_argocd
    install_argocd_cli
    setup_argocd_projects
  fi
  
  # 7. Setup ingress and networking
  if ask_approval "Setup ingress controllers and external access?"; then
    echo -e "${YELLOW}[7/7] Setting up ingress and networking...${NC}"
    source "./monitoring.sh"
    setup_grafana_ingress
    setup_prometheus_ingress
    setup_loki_ingress
    
    source "./cicd.sh"
    setup_argocd_ingress
    
    source "./databases.sh"
    setup_mongodb_ingress
  fi
}

function create_argocd_applications() {
  section "Creating ArgoCD Applications"
  
  if ask_approval "Create ArgoCD applications for infrastructure components?"; then
    source "./cicd.sh"
    create_mongodb_application
    create_monitoring_application
    setup_argocd_notifications
  fi
}

function show_deployment_summary() {
  section "Deployment Summary"
  
  local NODE_IP=$(hostname -I | awk '{print $1}')
  
  echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
  echo ""
  echo -e "${YELLOW}📊 Access URLs:${NC}"
  echo -e "  🔍 Grafana:     http://grafana.${NODE_IP}.nip.io (admin/prom-operator)"
  echo -e "  📈 Prometheus:  http://prometheus.${NODE_IP}.nip.io"
  echo -e "  📋 Loki:       http://loki.${NODE_IP}.nip.io"
  echo -e "  🚀 ArgoCD:     http://argocd.${NODE_IP}.nip.io (admin/[see below])"
  echo -e "  💾 PMM:        http://pmm.${NODE_IP}.nip.io (admin/admin-password)"
  echo ""
  
  echo -e "${YELLOW}🔐 Credentials:${NC}"
  echo -e "  Grafana: admin / prom-operator"
  echo -e "  PMM Server: admin / admin-password"
  
  # Get ArgoCD password
  local argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
  if [[ -n "$argocd_password" ]]; then
    echo -e "  ArgoCD: admin / $argocd_password"
  else
    echo -e "  ArgoCD: admin / [run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d]"
  fi
  
  echo ""
  echo -e "${YELLOW}🗄️  Database Information:${NC}"
  
  # MongoDB connection info
  local mongodb_endpoint=$(kubectl get psmdb psmdb -n database -o jsonpath='{.status.host}' 2>/dev/null)
  if [[ -n "$mongodb_endpoint" ]]; then
    echo -e "  MongoDB Cluster: $mongodb_endpoint"
    echo -e "  MongoDB Connection: mongodb://clusterAdmin:clusterAdmin123456@psmdb-mongos.database.svc.cluster.local/admin"
  else
    echo -e "  MongoDB: Not deployed or not ready"
  fi
  
  # Redis connection info
  if kubectl get service redis-master -n database &>/dev/null; then
    echo -e "  Redis: redis-master.database.svc.cluster.local:6379"
    echo -e "  Redis Password: secretpassword"
  else
    echo -e "  Redis: Not deployed"
  fi
  
  echo ""
  echo -e "${YELLOW}🔧 Management Commands:${NC}"
  echo -e "  Check status:     ./main.sh --status"
  echo -e "  Database status:  ./databases.sh"
  echo -e "  Monitoring:       ./monitoring.sh"
  echo -e "  CI/CD:           ./cicd.sh"
  echo -e "  Infrastructure:   ./infrastructure.sh"
  echo ""
  
  echo -e "${YELLOW}📚 Next Steps:${NC}"
  echo -e "  1. Access Grafana and explore the dashboards"
  echo -e "  2. Set up your Git repository for ArgoCD applications"
  echo -e "  3. Deploy your applications using ArgoCD"
  echo -e "  4. Configure monitoring alerts and notifications"
  echo -e "  5. Set up backup strategies for your databases"
  echo ""
  
  echo -e "${YELLOW}🆘 Troubleshooting:${NC}"
  echo -e "  • Check pod status: kubectl get pods --all-namespaces"
  echo -e "  • View logs: kubectl logs -n <namespace> <pod-name>"
  echo -e "  • MongoDB troubleshooting: ./databases.sh (option: Troubleshoot MongoDB)"
  echo -e "  • Monitoring status: ./monitoring.sh (option: Check Status)"
  echo ""
}

function check_deployment_status() {
  section "Checking Deployment Status"
  
  echo -e "${YELLOW}Kubernetes Cluster:${NC}"
  kubectl get nodes 2>/dev/null || echo "  ❌ Kubernetes not accessible"
  
  echo -e "\n${YELLOW}Namespaces:${NC}"
  kubectl get namespaces 2>/dev/null | grep -E "(database|monitoring|argocd|longhorn)" || echo "  ⚠️  Some namespaces missing"
  
  echo -e "\n${YELLOW}Storage Classes:${NC}"
  kubectl get storageclass 2>/dev/null || echo "  ❌ No storage classes found"
  
  echo -e "\n${YELLOW}Database Status:${NC}"
  if kubectl get psmdb psmdb -n database &>/dev/null; then
    local mongodb_status=$(kubectl get psmdb psmdb -n database -o jsonpath='{.status.state}' 2>/dev/null)
    echo -e "  MongoDB: ${mongodb_status:-unknown}"
  else
    echo -e "  MongoDB: ❌ Not deployed"
  fi
  
  if kubectl get deployment redis-master -n database &>/dev/null; then
    echo -e "  Redis: ✅ Deployed"
  else
    echo -e "  Redis: ❌ Not deployed"
  fi
  
  echo -e "\n${YELLOW}Monitoring Status:${NC}"
  if kubectl get deployment kube-prometheus-stack-grafana -n monitoring &>/dev/null; then
    echo -e "  Grafana: ✅ Deployed"
  else
    echo -e "  Grafana: ❌ Not deployed"
  fi
  
  if kubectl get service loki -n loki &>/dev/null; then
    echo -e "  Loki: ✅ Deployed"
  else
    echo -e "  Loki: ❌ Not deployed"
  fi
  
  echo -e "\n${YELLOW}CI/CD Status:${NC}"
  if kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo -e "  ArgoCD: ✅ Deployed"
    local app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    echo -e "  Applications: $app_count"
  else
    echo -e "  ArgoCD: ❌ Not deployed"
  fi
  
  echo -e "\n${YELLOW}Ingress Status:${NC}"
  local ingress_count=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)
  echo -e "  Total Ingresses: $ingress_count"
  
  if [[ $ingress_count -gt 0 ]]; then
    echo -e "  Ingress Controllers:"
    kubectl get ingress --all-namespaces 2>/dev/null | grep -v "NAMESPACE" | awk '{print "    " $2 " (" $1 ")"}'
  fi
}

function cleanup_deployment() {
  section "Cleanup Deployment"
  
  echo -e "${RED}⚠️  WARNING: This will remove ALL deployed components!${NC}"
  echo "This includes:"
  echo "• ArgoCD and all applications"
  echo "• Monitoring stack (Prometheus, Grafana, Loki)"
  echo "• Database clusters (MongoDB, Redis)"
  echo "• Storage systems (Longhorn)"
  echo "• Kubernetes cluster (K3s)"
  echo ""
  
  if ask_approval "Are you absolutely sure you want to proceed with cleanup?"; then
    echo -e "${YELLOW}Starting cleanup process...${NC}"
    
    # Cleanup in reverse order
    echo -e "${YELLOW}[1/6] Removing ArgoCD...${NC}"
    kubectl delete namespace argocd --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}[2/6] Removing monitoring stack...${NC}"
    helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
    helm uninstall loki -n loki 2>/dev/null || true
    kubectl delete namespace monitoring --timeout=120s 2>/dev/null || true
    kubectl delete namespace loki --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}[3/6] Removing databases...${NC}"
    kubectl delete psmdb psmdb -n database 2>/dev/null || true
    helm uninstall redis -n database 2>/dev/null || true
    kubectl delete namespace database --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}[4/6] Removing storage...${NC}"
    helm uninstall longhorn -n longhorn-system 2>/dev/null || true
    kubectl delete namespace longhorn-system --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}[5/6] Removing networking...${NC}"
    kubectl delete namespace metallb-system --timeout=120s 2>/dev/null || true
    kubectl delete namespace cert-manager --timeout=120s 2>/dev/null || true
    
    echo -e "${YELLOW}[6/6] Removing Kubernetes...${NC}"
    if command -v k3s-uninstall.sh &> /dev/null; then
      k3s-uninstall.sh
    fi
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
  else
    echo "Cleanup cancelled"
  fi
}

function main_menu() {
  while true; do
    echo ""
    echo -e "${BLUE}Wity Cloud Deploy - Main Menu${NC}"
    echo "================================"
    echo "1) Complete Infrastructure Deployment"
    echo "2) Check Deployment Status"
    echo "3) Deploy Individual Components"
    echo "4) Create ArgoCD Applications"
    echo "5) Show Deployment Summary"
    echo "6) Cleanup Deployment"
    echo "7) Exit"
    echo ""
    read -p "Select an option (1-7): " choice
    
    case $choice in
      1)
        show_banner
        check_prerequisites
        deploy_infrastructure
        create_argocd_applications
        show_deployment_summary
        ;;
      2)
        check_deployment_status
        ;;
      3)
        echo ""
        echo "Individual Component Deployment:"
        echo "a) Infrastructure (K3s, Storage, Networking)"
        echo "b) Databases (MongoDB, Redis)"
        echo "c) Monitoring (Prometheus, Grafana, Loki)"
        echo "d) CI/CD (ArgoCD)"
        echo ""
        read -p "Select component (a-d): " component
        
        case $component in
          a) source "./infrastructure.sh" ;;
          b) source "./databases.sh" ;;
          c) source "./monitoring.sh" ;;
          d) source "./cicd.sh" ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      4)
        create_argocd_applications
        ;;
      5)
        show_deployment_summary
        ;;
      6)
        cleanup_deployment
        ;;
      7)
        echo "Goodbye!"
        exit 0
        ;;
      *)
        echo "Invalid option. Please select 1-7."
        ;;
    esac
  done
}

# Handle command line arguments
case "${1:-}" in
  --status)
    check_deployment_status
    exit 0
    ;;
  --deploy)
    BATCH_MODE=true
    show_banner
    check_prerequisites
    deploy_infrastructure
    create_argocd_applications
    show_deployment_summary
    exit 0
    ;;
  --cleanup)
    cleanup_deployment
    exit 0
    ;;
  --help|-h)
    echo "Wity Cloud Deploy - Complete Infrastructure Deployment"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --deploy    Run complete deployment in batch mode"
    echo "  --status    Check deployment status"
    echo "  --cleanup   Remove all deployed components"
    echo "  --help      Show this help message"
    echo ""
    echo "Interactive mode (default): $0"
    exit 0
    ;;
  "")
    # Interactive mode
    show_banner
    main_menu
    ;;
  *)
    echo "Unknown option: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
esac
