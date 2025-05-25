#!/bin/bash

# Source common functions
if [[ -f "./common.sh" ]]; then
  source "./common.sh"
else
  echo "common.sh not found. This script requires common functions."
  exit 1
fi

function check_aws_route53() {
  section "Checking AWS Route53 Configuration"
  
  echo -e "${YELLOW}Testing AWS CLI configuration...${NC}"
  if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}AWS CLI is not properly configured${NC}"
    echo -e "${YELLOW}Please run: ./aws.sh and select 'AWS CLI Setup'${NC}"
    return 1
  fi
  
  echo -e "${GREEN}AWS CLI is configured${NC}"
  aws sts get-caller-identity
  
  echo -e "\n${YELLOW}Checking hosted zones...${NC}"
  aws route53 list-hosted-zones --query 'HostedZones[*].[Name,Id]' --output table 2>/dev/null || {
    echo -e "${RED}Failed to list hosted zones${NC}"
    return 1
  }
  
  echo -e "\n${YELLOW}Checking for dev.tese.io domain records...${NC}"
  ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "dev.tese.io." --query "HostedZones[0].Id" --output text 2>/dev/null)
  
  if [[ "$ZONE_ID" != "None" && -n "$ZONE_ID" ]]; then
    echo -e "${GREEN}Found hosted zone for dev.tese.io: $ZONE_ID${NC}"
    echo -e "\n${YELLOW}Current DNS records:${NC}"
    aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --query 'ResourceRecordSets[?Type==`A`].[Name,ResourceRecords[0].Value]' --output table
  else
    echo -e "${RED}No hosted zone found for dev.tese.io${NC}"
    echo -e "${YELLOW}You need to create a hosted zone for dev.tese.io in Route53${NC}"
  fi
}

function fix_https_redirect_issues() {
  section "Fixing HTTPS Redirect Issues for All Services"
  
  # Services that need fixing
  SERVICES=("pgadmin" "rancher" "loki" "prometheus" "grafana")
  NAMESPACES=("pgadmin" "cattle-system" "default" "monitoring" "monitoring")
  
  local NODE_IP=$(hostname -I | awk '{print $1}')
  
  for i in "${!SERVICES[@]}"; do
    SERVICE="${SERVICES[$i]}"
    NAMESPACE="${NAMESPACES[$i]}"
    
    echo -e "\n${YELLOW}Checking $SERVICE in namespace $NAMESPACE...${NC}"
    
    # Check if ingress exists
    if kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" &>/dev/null; then
      MIDDLEWARE=$(kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares}' 2>/dev/null || echo "")
      
      if [[ "$MIDDLEWARE" == *"redirect-https"* ]]; then
        echo -e "${YELLOW}Found $SERVICE ingress with HTTPS redirect. Fixing...${NC}"
        
        # Remove HTTPS redirect middleware
        kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p='[{"op": "remove", "path": "/metadata/annotations/traefik.ingress.kubernetes.io~1router.middlewares"}]' 2>/dev/null || true
        
        # Clean up failed certificates and TLS sections
        kubectl delete certificate "${SERVICE}-tls" -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete certificaterequest "${SERVICE}-tls-1" -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete secret "${SERVICE}-tls-secret" -n "$NAMESPACE" --ignore-not-found=true
        
        # Remove TLS section from ingress
        kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p='[{"op": "remove", "path": "/spec/tls"}]' 2>/dev/null || true
        
        echo -e "${GREEN}Removed HTTPS redirect and TLS from $SERVICE ingress${NC}"
      fi
      
      # Add nip.io domain to existing ingress (keep both domains)
      echo -e "${YELLOW}Adding nip.io domain to $SERVICE ingress...${NC}"
      add_nip_io_to_ingress "$SERVICE" "$NAMESPACE" "$NODE_IP"
      
    else
      echo -e "${YELLOW}No ingress found for $SERVICE${NC}"
      
      # Create HTTP-only ingress for the service
      create_http_ingress "$SERVICE" "$NAMESPACE"
    fi
  done
  
  # Clean up ACME solver ingresses
  echo -e "\n${YELLOW}Cleaning up ACME solver ingresses...${NC}"
  kubectl delete ingress --all-namespaces -l acme.cert-manager.io/http01-solver=true --ignore-not-found=true
}

function add_nip_io_to_ingress() {
  local SERVICE=$1
  local NAMESPACE=$2
  local NODE_IP=$3
  
  # Determine service name and port based on service type
  case $SERVICE in
    "pgadmin")
      SERVICE_NAME="pgadmin"
      SERVICE_PORT="80"
      ;;
    "rancher")
      SERVICE_NAME="rancher"
      SERVICE_PORT="80"
      ;;
    "loki")
      SERVICE_NAME="loki"
      SERVICE_PORT="3100"
      ;;
    "prometheus")
      SERVICE_NAME="kube-prometheus-stack-prometheus"
      SERVICE_PORT="9090"
      ;;
    "grafana")
      SERVICE_NAME="kube-prometheus-stack-grafana"
      SERVICE_PORT="80"
      ;;
  esac
  
  # Get current ingress configuration
  local CURRENT_RULES=$(kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules}')
  
  # Check if nip.io domain already exists
  if echo "$CURRENT_RULES" | grep -q "${SERVICE}.${NODE_IP}.nip.io"; then
    echo -e "${GREEN}nip.io domain already exists for $SERVICE${NC}"
    return
  fi
  
  # Add the nip.io rule to the existing ingress
  kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p="[{
    \"op\": \"add\",
    \"path\": \"/spec/rules/-\",
    \"value\": {
      \"host\": \"${SERVICE}.${NODE_IP}.nip.io\",
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
  
  echo -e "${GREEN}Added nip.io domain to $SERVICE ingress: http://${SERVICE}.${NODE_IP}.nip.io${NC}"
}

function create_http_ingress() {
  local SERVICE=$1
  local NAMESPACE=$2
  local NODE_IP=$(hostname -I | awk '{print $1}')
  
  echo -e "${YELLOW}Creating HTTP-only ingress for $SERVICE...${NC}"
  
  # Determine service name and port based on service type
  case $SERVICE in
    "pgadmin")
      SERVICE_NAME="pgadmin"
      SERVICE_PORT="80"
      ;;
    "rancher")
      SERVICE_NAME="rancher"
      SERVICE_PORT="80"
      ;;
    "loki")
      SERVICE_NAME="loki"
      SERVICE_PORT="3100"
      ;;
    "prometheus")
      SERVICE_NAME="kube-prometheus-stack-prometheus"
      SERVICE_PORT="9090"
      ;;
    "grafana")
      SERVICE_NAME="kube-prometheus-stack-grafana"
      SERVICE_PORT="80"
      ;;
  esac
  
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${SERVICE}-ingress
  namespace: ${NAMESPACE}
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: ${SERVICE}.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${SERVICE_NAME}
            port:
              number: ${SERVICE_PORT}
EOF

  echo -e "${GREEN}Created HTTP ingress for $SERVICE at: http://${SERVICE}.${NODE_IP}.nip.io${NC}"
}

function check_service_status() {
  section "Checking Service Status"
  
  echo -e "${YELLOW}Checking PgAdmin...${NC}"
  kubectl get pods,svc,ingress -n pgadmin 2>/dev/null || echo "PgAdmin not found"
  
  echo -e "\n${YELLOW}Checking Rancher...${NC}"
  kubectl get pods,svc,ingress -n cattle-system | grep rancher
  
  echo -e "\n${YELLOW}Checking Loki...${NC}"
  kubectl get pods,svc,ingress -n default | grep loki
  
  echo -e "\n${YELLOW}Checking Monitoring (Grafana/Prometheus)...${NC}"
  kubectl get pods,svc,ingress -n monitoring
}

function test_ingress_connectivity() {
  section "Testing Ingress Connectivity"
  
  local NODE_IP=$(hostname -I | awk '{print $1}')
  
  echo -e "${YELLOW}Testing HTTP connectivity to services...${NC}"
  
  SERVICES=("grafana" "prometheus" "pgadmin" "rancher")
  
  for SERVICE in "${SERVICES[@]}"; do
    echo -e "\n${YELLOW}Testing $SERVICE...${NC}"
    
    # Test nip.io domain
    URL_NIP="http://${SERVICE}.${NODE_IP}.nip.io"
    echo -e "  ${YELLOW}Testing nip.io: $URL_NIP${NC}"
    
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$URL_NIP" | grep -q "200\|302\|401"; then
      echo -e "  ${GREEN}✓ $SERVICE is accessible via nip.io${NC}"
    else
      echo -e "  ${RED}✗ $SERVICE is not accessible via nip.io${NC}"
    fi
    
    # Test dev.tese.io domain
    URL_DEV="http://${SERVICE}.dev.tese.io"
    echo -e "  ${YELLOW}Testing dev.tese.io: $URL_DEV${NC}"
    
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$URL_DEV" | grep -q "200\|302\|401"; then
      echo -e "  ${GREEN}✓ $SERVICE is accessible via dev.tese.io${NC}"
    else
      echo -e "  ${RED}✗ $SERVICE is not accessible via dev.tese.io (may need Route53 setup)${NC}"
    fi
    
    # Check if service exists if both fail
    if ! curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$URL_NIP" | grep -q "200\|302\|401" && \
       ! curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$URL_DEV" | grep -q "200\|302\|401"; then
      echo -e "  ${YELLOW}Checking service status...${NC}"
      case $SERVICE in
        "grafana"|"prometheus")
          kubectl get svc -n monitoring | grep "$SERVICE" || echo "  Service not found"
          ;;
        "pgadmin")
          kubectl get svc -n pgadmin | grep "$SERVICE" || echo "  Service not found"
          ;;
        "rancher")
          kubectl get svc -n cattle-system | grep "$SERVICE" || echo "  Service not found"
          ;;
      esac
    fi
  done
}

function create_route53_records() {
  section "Creating Route53 Records for Services"
  
  if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}AWS CLI not configured. Please run ./aws.sh first${NC}"
    return 1
  fi
  
  local PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
  local ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "dev.tese.io." --query "HostedZones[0].Id" --output text 2>/dev/null)
  
  if [[ "$ZONE_ID" == "None" || -z "$ZONE_ID" ]]; then
    echo -e "${RED}No hosted zone found for dev.tese.io${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Creating A records for services pointing to $PUBLIC_IP...${NC}"
  
  SERVICES=("pgadmin" "loki" "rancher" "grafana" "prometheus")
  
  for SERVICE in "${SERVICES[@]}"; do
    echo -e "${YELLOW}Creating record for ${SERVICE}.dev.tese.io...${NC}"
    
    cat <<EOF > /tmp/${SERVICE}-record.json
{
  "Comment": "Create A record for ${SERVICE}.dev.tese.io",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${SERVICE}.dev.tese.io",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{
        "Value": "${PUBLIC_IP}"
      }]
    }
  }]
}
EOF
    
    if aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/${SERVICE}-record.json; then
      echo -e "${GREEN}✓ Created ${SERVICE}.dev.tese.io -> $PUBLIC_IP${NC}"
    else
      echo -e "${RED}✗ Failed to create ${SERVICE}.dev.tese.io${NC}"
    fi
    
    rm -f /tmp/${SERVICE}-record.json
  done
}

function show_access_summary() {
  section "Service Access Summary"
  
  local NODE_IP=$(hostname -I | awk '{print $1}')
  local PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
  
  echo "=================================================="
  echo "Service Access URLs:"
  echo "=================================================="
  echo "Local Access (nip.io - always works):"
  echo "  - Grafana:    http://grafana.${NODE_IP}.nip.io"
  echo "  - Prometheus: http://prometheus.${NODE_IP}.nip.io"
  echo "  - PgAdmin:    http://pgadmin.${NODE_IP}.nip.io"
  echo "  - Rancher:    http://rancher.${NODE_IP}.nip.io"
  echo "  - Loki:       http://loki.${NODE_IP}.nip.io"
  echo ""
  echo "Public Access (dev.tese.io - requires Route53 setup):"
  echo "  - Grafana:    http://grafana.dev.tese.io"
  echo "  - Prometheus: http://prometheus.dev.tese.io"
  echo "  - PgAdmin:    http://pgadmin.dev.tese.io"
  echo "  - Rancher:    http://rancher.dev.tese.io"
  echo "  - Loki:       http://loki.dev.tese.io"
  echo ""
  echo "Port-forward alternatives (localhost access):"
  echo "  - Grafana:    kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
  echo "                Then visit: http://localhost:3000"
  echo "  - Prometheus: kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring"
  echo "                Then visit: http://localhost:9090"
  echo "  - PgAdmin:    kubectl port-forward svc/pgadmin 8080:80 -n pgadmin"
  echo "                Then visit: http://localhost:8080"
  echo "  - Rancher:    kubectl port-forward svc/rancher 8443:443 -n cattle-system"
  echo "                Then visit: https://localhost:8443"
  echo ""
  echo "Note: Both domains (nip.io and dev.tese.io) are configured for each service."
  echo "      nip.io domains work immediately, dev.tese.io requires DNS setup."
  echo "=================================================="
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "=== Comprehensive Ingress and DNS Troubleshooting ==="
  
  PS3='Select action: '
  options=(
    "Check AWS Route53 Configuration"
    "Fix HTTPS Redirect Issues"
    "Check Service Status"
    "Test Ingress Connectivity"
    "Create Route53 Records"
    "Show Access Summary"
    "Fix All Issues (Comprehensive)"
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Check AWS Route53 Configuration")
        check_aws_route53
        ;;
      "Fix HTTPS Redirect Issues")
        fix_https_redirect_issues
        ;;
      "Check Service Status")
        check_service_status
        ;;
      "Test Ingress Connectivity")
        test_ingress_connectivity
        ;;
      "Create Route53 Records")
        create_route53_records
        ;;
      "Show Access Summary")
        show_access_summary
        ;;
      "Fix All Issues (Comprehensive)")
        check_aws_route53
        fix_https_redirect_issues
        check_service_status
        test_ingress_connectivity
        show_access_summary
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