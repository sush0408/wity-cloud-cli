#!/bin/bash

# Main deployment orchestration script
# This script coordinates the deployment of the complete infrastructure stack

# Source common functions
  source "./common.sh"

# Global configuration
BATCH_MODE=${BATCH_MODE:-false}
SKIP_CONFIRMATIONS=${SKIP_CONFIRMATIONS:-false}

# Services and their namespaces for HTTPS setup
declare -A HTTPS_SERVICES=(
  ["grafana"]="monitoring"
  ["prometheus"]="monitoring"
  ["pgadmin"]="pgadmin"
  ["rancher"]="cattle-system"
  ["loki"]="loki"
  ["argocd"]="argocd"
  ["pmm"]="monitoring"
)

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
  echo "• HTTPS certificates for all services"
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

function setup_https_certificates() {
  section "Setting up HTTPS certificates for dev.tese.io domains"
  
  echo -e "${YELLOW}Creating Let's Encrypt certificates for all services...${NC}"
  
  for service in "${!HTTPS_SERVICES[@]}"; do
    namespace="${HTTPS_SERVICES[$service]}"
    domain="${service}.dev.tese.io"
    
    echo -e "\n${YELLOW}Creating certificate for ${domain}...${NC}"
    
    # Create certificate
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${service}-tls-cert
  namespace: ${namespace}
spec:
  secretName: ${service}-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: ${domain}
  dnsNames:
  - ${domain}
EOF
    
    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}✅ Certificate created for ${domain}${NC}"
    else
      echo -e "${RED}❌ Failed to create certificate for ${domain}${NC}"
    fi
  done
}

function fix_ingress_https_configuration() {
  section "Configuring ingresses for proper HTTPS access"
  
  for service in "${!HTTPS_SERVICES[@]}"; do
    namespace="${HTTPS_SERVICES[$service]}"
    domain="${service}.dev.tese.io"
    ingress_name="${service}-ingress"
    
    # Special case for different ingress names
    if [[ "$service" == "rancher" ]]; then
      ingress_name="rancher"
    elif [[ "$service" == "argocd" ]]; then
      ingress_name="argocd-server-ingress"
    fi
    
    echo -e "\n${YELLOW}Updating ${ingress_name} in namespace ${namespace}...${NC}"
    
    # Check if ingress exists
    if kubectl get ingress "$ingress_name" -n "$namespace" &>/dev/null; then
      
      # Remove any existing TLS configuration first
      kubectl patch ingress "$ingress_name" -n "$namespace" --type='json' -p='[{"op": "remove", "path": "/spec/tls"}]' 2>/dev/null || true
      
      # Add proper TLS configuration
      kubectl patch ingress "$ingress_name" -n "$namespace" --type='json' -p="[{
        \"op\": \"add\",
        \"path\": \"/spec/tls\",
        \"value\": [{
          \"hosts\": [\"${domain}\"],
          \"secretName\": \"${service}-tls-secret\"
        }]
      }]"
      
      # Fix entrypoints to accept both HTTP and HTTPS and add cert-manager annotation
      kubectl annotate ingress "$ingress_name" -n "$namespace" \
        cert-manager.io/cluster-issuer=letsencrypt-prod \
        traefik.ingress.kubernetes.io/router.entrypoints=web,websecure \
        --overwrite
      
      # Remove problematic middleware if it exists
      kubectl annotate ingress "$ingress_name" -n "$namespace" \
        traefik.ingress.kubernetes.io/router.middlewares- \
        --overwrite 2>/dev/null || true
      
      # Check if the dev.tese.io host exists in the ingress
      HOSTS=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.spec.rules[*].host}')
      if [[ "$HOSTS" != *"${domain}"* ]]; then
        echo -e "${YELLOW}Adding ${domain} to ingress rules...${NC}"
        
        # Get the service name and port from existing rules
        SERVICE_NAME=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
        SERVICE_PORT=$(kubectl get ingress "$ingress_name" -n "$namespace" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}')
        
        # Add the dev.tese.io rule
        kubectl patch ingress "$ingress_name" -n "$namespace" --type='json' -p="[{
          \"op\": \"add\",
          \"path\": \"/spec/rules/-\",
          \"value\": {
            \"host\": \"${domain}\",
            \"http\": {
              \"paths\": [{
                \"path\": \"/\",
                \"pathType\": \"Prefix\",
                \"backend\": {
                  \"service\": {
                    \"name\": \"${SERVICE_NAME}\",
                    \"port\": {
                      \"number\": ${SERVICE_PORT}
                    }
                  }
                }
              }]
            }
          }
        }]"
      fi
      
      echo -e "${GREEN}✅ Updated ${ingress_name} for HTTPS${NC}"
    else
      echo -e "${YELLOW}⚠️  Ingress ${ingress_name} not found in namespace ${namespace}${NC}"
  fi
done

  # Wait a moment for ingress changes to be processed
  echo -e "${YELLOW}Waiting for ingress changes to be processed...${NC}"
  sleep 10
}

function verify_https_access() {
  section "Verifying HTTPS access for all services"
  
  echo -e "${YELLOW}Testing HTTPS connectivity for all dev.tese.io domains...${NC}"
  
  for service in "${!HTTPS_SERVICES[@]}"; do
    domain="${service}.dev.tese.io"
    echo -e "\n${YELLOW}Testing ${domain}...${NC}"
    
    # Test HTTPS connectivity
    if curl -s -I --connect-timeout 10 "https://${domain}" | head -1 | grep -q "HTTP"; then
      echo -e "${GREEN}✅ ${domain} - HTTPS working${NC}"
    else
      echo -e "${RED}❌ ${domain} - HTTPS not accessible${NC}"
      
      # Check certificate status
      cert_name="${service}-tls-cert"
      namespace="${HTTPS_SERVICES[$service]}"
      cert_status=$(kubectl get certificate "$cert_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      
      if [[ "$cert_status" == "True" ]]; then
        echo -e "${YELLOW}  Certificate is ready, checking ingress...${NC}"
      else
        echo -e "${YELLOW}  Certificate not ready: $cert_status${NC}"
      fi
    fi
  done
  
  echo -e "\n${YELLOW}HTTPS verification complete!${NC}"
}

function deploy_infrastructure() {
  section "Deploying Infrastructure Components"
  
  # 1. Deploy Kubernetes cluster
  if ask_approval "Deploy K3s Kubernetes cluster?"; then
    echo -e "${YELLOW}[1/8] Deploying K3s...${NC}"
    source "./core.sh"
    install_rke2_server
    install_helm
    add_helm_repos
    install_metallb
  fi
  
  # 2. Deploy storage
  if ask_approval "Deploy Longhorn storage?"; then
    echo -e "${YELLOW}[2/8] Deploying Longhorn storage...${NC}"
    source "./storage.sh"
    install_longhorn
  fi
  
  # 3. Deploy cert-manager for HTTPS
  if ask_approval "Deploy cert-manager for HTTPS certificates?"; then
    echo -e "${YELLOW}[3/8] Deploying cert-manager...${NC}"
    source "./management.sh"
    install_cert_manager
    
    # Create Let's Encrypt ClusterIssuer
    echo -e "${YELLOW}Creating Let's Encrypt ClusterIssuer...${NC}"
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@dev.tese.io
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
  fi
  
  # 4. Deploy databases
  if ask_approval "Deploy database stack (MongoDB + Redis)?"; then
    echo -e "${YELLOW}[4/8] Deploying databases...${NC}"
    source "./databases.sh"
    install_mongodb_percona
    install_redis_bitnami
  fi
  
  # 5. Deploy monitoring
  if ask_approval "Deploy monitoring stack (Prometheus + Grafana + Loki)?"; then
    echo -e "${YELLOW}[5/8] Deploying monitoring...${NC}"
    source "./monitoring.sh"
    install_monitoring
    install_loki
    configure_loki_datasource
  fi
  
  # 6. Deploy PMM for database monitoring
  if ask_approval "Deploy PMM Server for database monitoring?"; then
    echo -e "${YELLOW}[6/8] Deploying PMM Server...${NC}"
    source "./databases.sh"
    install_pmm_server_for_mongodb
  fi
  
  # 7. Deploy CI/CD (ArgoCD)
  if ask_approval "Deploy ArgoCD for GitOps CI/CD?"; then
    echo -e "${YELLOW}[7/8] Deploying ArgoCD...${NC}"
    source "./cicd.sh"
    install_argocd
    install_argocd_cli
    setup_argocd_projects
  fi
  
  # 8. Setup ingress and HTTPS
  if ask_approval "Setup ingress controllers and HTTPS certificates?"; then
    echo -e "${YELLOW}[8/8] Setting up ingress and HTTPS...${NC}"
    
    # Setup ingresses
    source "./monitoring.sh"
    setup_grafana_ingress
    setup_prometheus_ingress
    setup_loki_ingress
    
    source "./cicd.sh"
    setup_argocd_ingress
    
    source "./databases.sh"
    setup_mongodb_ingress
    
    source "./management.sh"
    setup_pgadmin_ingress
    setup_rancher_ingress
    
    # Setup HTTPS certificates
    setup_https_certificates
    
    # Wait a moment for certificates to be processed
    echo -e "${YELLOW}Waiting for certificates to be processed...${NC}"
    sleep 30
    
    # Fix ingress configurations
    fix_ingress_https_configuration
    
    # Verify HTTPS access
    verify_https_access
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
  echo -e "${YELLOW}🔒 HTTPS Access URLs (dev.tese.io):${NC}"
  echo -e "  🔍 Grafana:     https://grafana.dev.tese.io (admin/prom-operator)"
  echo -e "  📈 Prometheus:  https://prometheus.dev.tese.io"
  echo -e "  📋 Loki:       https://loki.dev.tese.io"
  echo -e "  🚀 ArgoCD:     https://argocd.dev.tese.io (admin/[see below])"
  echo -e "  💾 PMM:        https://pmm.dev.tese.io (admin/admin-password)"
  echo -e "  🗄️  pgAdmin:    https://pgadmin.dev.tese.io (admin@admin.com/admin)"
  echo -e "  🐄 Rancher:    https://rancher.dev.tese.io"
  echo ""
  echo -e "${YELLOW}📊 Alternative Access URLs (nip.io):${NC}"
  echo -e "  🔍 Grafana:     http://grafana.${NODE_IP}.nip.io"
  echo -e "  📈 Prometheus:  http://prometheus.${NODE_IP}.nip.io"
  echo -e "  📋 Loki:       http://loki.${NODE_IP}.nip.io"
  echo -e "  🚀 ArgoCD:     http://argocd.${NODE_IP}.nip.io"
  echo -e "  💾 PMM:        http://pmm.${NODE_IP}.nip.io"
  echo -e "  🗄️  pgAdmin:    http://pgadmin.${NODE_IP}.nip.io"
  echo -e "  🐄 Rancher:    http://rancher.${NODE_IP}.nip.io"
  echo ""
  
  echo -e "${YELLOW}🔐 Credentials:${NC}"
  echo -e "  Grafana: admin / prom-operator"
  echo -e "  PMM Server: admin / admin-password"
  echo -e "  pgAdmin: admin@admin.com / admin"
  
  # Get ArgoCD password
  local argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
  if [[ -n "$argocd_password" ]]; then
    echo -e "  ArgoCD: admin / $argocd_password"
  else
    echo -e "  ArgoCD: admin / [run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d]"
  fi
  
  # Get Rancher password
  echo -e "  Rancher: [Bootstrap password will be shown on first access]"
  
  echo ""
  echo -e "${YELLOW}🗄️  Database Information:${NC}"
  
  # MongoDB connection info
  local mongodb_endpoint=$(kubectl get psmdb psmdb -n pgo -o jsonpath='{.status.host}' 2>/dev/null)
  if [[ -n "$mongodb_endpoint" ]]; then
    echo -e "  MongoDB Cluster: $mongodb_endpoint"
    echo -e "  MongoDB Connection: mongodb://databaseAdmin:databaseAdmin123456@psmdb-mongos.pgo.svc.cluster.local/admin"
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
  echo -e "  Infrastructure:   ./core.sh"
  echo ""
  
  echo -e "${YELLOW}📚 Next Steps:${NC}"
  echo -e "  1. Access Grafana and explore the dashboards"
  echo -e "  2. Set up your Git repository for ArgoCD applications"
  echo -e "  3. Deploy your applications using ArgoCD"
  echo -e "  4. Configure monitoring alerts and notifications"
  echo -e "  5. Set up backup strategies for your databases"
  echo ""
  
  echo -e "${YELLOW}🔒 HTTPS Certificate Status:${NC}"
  echo -e "  Check certificate status: kubectl get certificates --all-namespaces"
  echo -e "  All services are configured with Let's Encrypt certificates"
  echo -e "  DNS must point *.dev.tese.io to ${NODE_IP} for HTTPS to work"
  echo ""
  
  echo -e "${YELLOW}🆘 Troubleshooting:${NC}"
  echo -e "  • Check pod status: kubectl get pods --all-namespaces"
  echo -e "  • View logs: kubectl logs -n <namespace> <pod-name>"
  echo -e "  • MongoDB troubleshooting: ./databases.sh (option: Troubleshoot MongoDB)"
  echo -e "  • Monitoring status: ./monitoring.sh (option: Check Status)"
  echo -e "  • Certificate issues: kubectl describe certificate <cert-name> -n <namespace>"
  echo ""
}

function check_deployment_status() {
  section "Checking Deployment Status"
  
  echo -e "${YELLOW}Kubernetes Cluster:${NC}"
  kubectl get nodes 2>/dev/null || echo "  ❌ Kubernetes not accessible"
  
  echo -e "\n${YELLOW}Namespaces:${NC}"
  kubectl get namespaces 2>/dev/null | grep -E "(pgo|database|monitoring|argocd|longhorn|loki|cert-manager)" || echo "  ⚠️  Some namespaces missing"
  
  echo -e "\n${YELLOW}Storage Classes:${NC}"
  kubectl get storageclass 2>/dev/null || echo "  ❌ No storage classes found"
  
  echo -e "\n${YELLOW}Database Status:${NC}"
  # Check MongoDB in pgo namespace (Percona)
  if kubectl get psmdb psmdb -n pgo &>/dev/null; then
    local mongodb_status=$(kubectl get psmdb psmdb -n pgo -o jsonpath='{.status.state}' 2>/dev/null)
    echo -e "  MongoDB (Percona): ${mongodb_status:-unknown}"
  elif kubectl get psmdb psmdb -n database &>/dev/null; then
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
  
  if kubectl get deployment pmm-server -n monitoring &>/dev/null; then
    echo -e "  PMM Server: ✅ Deployed"
  else
    echo -e "  PMM Server: ❌ Not deployed"
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
  
  echo -e "\n${YELLOW}HTTPS Certificate Status:${NC}"
  if kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
    echo -e "  Let's Encrypt ClusterIssuer: ✅ Ready"
  else
    echo -e "  Let's Encrypt ClusterIssuer: ❌ Not found"
  fi
  
  local cert_count=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null | wc -l)
  echo -e "  Total Certificates: $cert_count"
  
  if [[ $cert_count -gt 0 ]]; then
    echo -e "  Certificate Status:"
    for service in "${!HTTPS_SERVICES[@]}"; do
      namespace="${HTTPS_SERVICES[$service]}"
      cert_name="${service}-tls-cert"
      
      if kubectl get certificate "$cert_name" -n "$namespace" &>/dev/null; then
        local cert_status=$(kubectl get certificate "$cert_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [[ "$cert_status" == "True" ]]; then
          echo -e "    ${service}.dev.tese.io: ✅ Ready"
        else
          echo -e "    ${service}.dev.tese.io: ⚠️  Pending"
        fi
      else
        echo -e "    ${service}.dev.tese.io: ❌ Not found"
      fi
    done
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
    echo "5) Fix HTTPS Configuration"
    echo "6) Show Deployment Summary"
    echo "7) Cleanup Deployment"
    echo "8) Exit"
    echo ""
    read -p "Select an option (1-8): " choice
    
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
          a) 
            echo -e "${YELLOW}Launching Infrastructure deployment...${NC}"
            bash "./core.sh"
            ;;
          b) 
            echo -e "${YELLOW}Launching Database deployment...${NC}"
            bash "./databases.sh"
            ;;
          c) 
            echo -e "${YELLOW}Launching Monitoring deployment...${NC}"
            bash "./monitoring.sh"
            ;;
          d) 
            echo -e "${YELLOW}Launching CI/CD deployment...${NC}"
            bash "./cicd.sh"
            ;;
          *) echo "Invalid option" ;;
        esac
        ;;
      4)
        create_argocd_applications
        ;;
      5)
        echo -e "${YELLOW}Fixing HTTPS configuration for all services...${NC}"
        setup_https_certificates
        fix_ingress_https_configuration
        verify_https_access
        ;;
      6)
        show_deployment_summary
        ;;
      7)
        cleanup_deployment
        ;;
      8)
        echo "Goodbye!"
        exit 0
        ;;
      *)
        echo "Invalid option. Please select 1-8."
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
  --fix-https)
    echo -e "${YELLOW}Fixing HTTPS configuration for all services...${NC}"
    setup_https_certificates
    fix_ingress_https_configuration
    verify_https_access
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
    echo "  --deploy      Run complete deployment in batch mode"
    echo "  --status      Check deployment status"
    echo "  --fix-https   Fix HTTPS configuration for all services"
    echo "  --cleanup     Remove all deployed components"
    echo "  --help        Show this help message"
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
