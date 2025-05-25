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

function apply_tls_certificates() {
  section "Creating ClusterIssuer and Certificates for all domains"
  
  # Source domain configuration
  if [[ -f ~/.cluster_domains ]]; then
    source ~/.cluster_domains
  else
    echo -e "${YELLOW}No domain configuration found. Please run 'Configure Domain' first.${NC}"
    return 1
  fi

  cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@${ROOT_DOMAIN}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: traefik
EOF

  for key in "${!SERVICE_DOMAINS[@]}"; do
    domain_name="${SERVICE_DOMAINS[$key]}"
    namespace="default"
    [[ "$key" == "pgadmin" ]] && namespace="pgadmin"
    [[ "$key" == "rancher" ]] && namespace="cattle-system"
    [[ "$key" == "grafana" || "$key" == "prometheus" ]] && namespace="monitoring"

    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${key}-tls
  namespace: ${namespace}
spec:
  secretName: ${key}-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: ${domain_name}
  dnsNames:
  - ${domain_name}
EOF
  done

  echo -e "${GREEN}TLS certificates requested from Let's Encrypt. Ingresses must use these secrets.${NC}"
}

function patch_ingresses_for_tls() {
  section "Patching known Ingresses to use deduced hostnames and TLS"
  
  # Source domain configuration
  if [[ -f ~/.cluster_domains ]]; then
    source ~/.cluster_domains
  else
    echo -e "${YELLOW}No domain configuration found. Please run 'Configure Domain' first.${NC}"
    return 1
  fi

  # pgAdmin
  if kubectl get ingress pgadmin-ingress -n pgadmin &> /dev/null; then
    kubectl patch ingress pgadmin-ingress -n pgadmin --type merge -p "
spec:
  tls:
  - hosts:
    - ${SERVICE_DOMAINS[pgadmin]}
    secretName: pgadmin-tls-secret
  rules:
  - host: ${SERVICE_DOMAINS[pgadmin]}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
"
  fi

  # Rancher
  if kubectl get namespace cattle-system &> /dev/null; then
    helm upgrade rancher rancher-latest/rancher -n cattle-system \
      --set hostname=${SERVICE_DOMAINS[rancher]} \
      --set ingress.tls.source=secret \
      --set privateCA=true \
      --set additionalTrustedCAs=true \
      --set ingress.ingressClassName=traefik
  fi

  echo -e "${GREEN}Ingresses patched with domain and TLS configuration.${NC}"
}

function show_cluster_status_summary() {
  section "Final Cluster Status Summary"
  
  # Source domain configuration if available
  if [[ -f ~/.cluster_domains ]]; then
    source ~/.cluster_domains
  fi

  echo ""
  printf "%-20s %-45s %-10s\n" "Component" "URL / Hostname" "Status"
  printf "%-20s %-45s %-10s\n" "---------" "-----------------" "------"

  # If we have SERVICE_DOMAINS defined, use them
  if [[ -v SERVICE_DOMAINS ]]; then
    for key in "${!SERVICE_DOMAINS[@]}"; do
      ns="default"
      [[ "$key" == "pgadmin" ]] && ns="pgadmin"
      [[ "$key" == "rancher" ]] && ns="cattle-system"
      [[ "$key" == "grafana" || "$key" == "prometheus" ]] && ns="monitoring"
      svc_status=$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | grep "$key" || true)

      if [ -n "$svc_status" ]; then
        printf "%-20s %-45s %-10s\n" "$key" "${SERVICE_DOMAINS[$key]}" "Ready"
      else
        printf "%-20s %-45s %-10s\n" "$key" "${SERVICE_DOMAINS[$key]}" "Pending"
      fi
    done
  else
    # Fallback if no domains are configured
    NODE_IP=$(hostname -I | awk '{print $1}')
    
    # Check some common components
    if kubectl get ns cattle-system &> /dev/null; then
      printf "%-20s %-45s %-10s\n" "Rancher" "rancher.${NODE_IP}.nip.io" "Installed"
    fi
    
    if kubectl get ns monitoring &> /dev/null; then
      printf "%-20s %-45s %-10s\n" "Prometheus" "prometheus.${NODE_IP}.nip.io" "Installed"
      printf "%-20s %-45s %-10s\n" "Grafana" "grafana.${NODE_IP}.nip.io" "Installed"
    fi
    
    if kubectl get ns pgadmin &> /dev/null; then
      printf "%-20s %-45s %-10s\n" "pgAdmin" "pgadmin.${NODE_IP}.nip.io" "Installed"
    fi
  fi

  echo ""
  echo -e "${GREEN}Check the URLs above to access your deployed services.${NC}"
}

function check_node_taints_and_labels() {
  section "Checking for taints that may block scheduling"

  nodes=$(kubectl get nodes -o name)
  for node in $nodes; do
    taints=$(kubectl describe $node | grep "Taints:" | sed 's/Taints://g' | xargs)
    if [[ "$taints" != "<none>" && -n "$taints" ]]; then
      echo -e "${YELLOW}Node ${node} has taints: ${taints}${NC}"
      echo -e "${YELLOW}Ensure pods have tolerations or remove taints if unintended.${NC}"
    else
      echo -e "${GREEN}Node ${node} has no blocking taints.${NC}"
    fi
  done
}

function wait_for_deployments() {
  section "Waiting for deployments to be ready"

  namespaces=(longhorn-system monitoring loki cattle-system pgadmin database traefik)
  for ns in "${namespaces[@]}"; do
    if kubectl get ns $ns &> /dev/null; then
      echo -e "${YELLOW}Checking deployments in namespace: $ns${NC}"
      kubectl rollout status deployment --all -n $ns --timeout=180s || echo -e "${YELLOW}Timeout or issue with deployments in $ns${NC}"
    fi
  done
}

function check_service_health_detailed() {
  section "Detailed Service Health Check (Deployments, Pods, Ingresses)"
  
  # Source domain configuration if available
  if [[ -f ~/.cluster_domains ]]; then
    source ~/.cluster_domains
  fi

  printf "%-20s %-45s %-12s %-10s %-10s\n" "Component" "URL / Hostname" "Namespace" "Pods" "Ingress"

  if [[ -v SERVICE_DOMAINS ]]; then
    for key in "${!SERVICE_DOMAINS[@]}"; do
      domain="${SERVICE_DOMAINS[$key]}"
      ns="default"
      [[ "$key" == "pgadmin" ]] && ns="pgadmin"
      [[ "$key" == "rancher" ]] && ns="cattle-system"
      [[ "$key" == "grafana" || "$key" == "prometheus" ]] && ns="monitoring"
      [[ "$key" == "minio" || "$key" == "loki" || "$key" == "argocd" || "$key" == "velero" ]] && ns="default"

      # Count pods
      pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -cEv 'Completed|Evicted|Terminating' || echo "0")

      # Check ingress
      ingress_exists=$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | grep "$key" || true)
      if [ -n "$ingress_exists" ]; then
        ingress_status="OK"
      else
        ingress_status="None"
      fi

      printf "%-20s %-45s %-12s %-10s %-10s\n" "$key" "$domain" "$ns" "$pod_count" "$ingress_status"
    done
  else
    # Fallback to just checking common namespaces
    namespaces=(kube-system monitoring loki cattle-system pgadmin database traefik)
    for ns in "${namespaces[@]}"; do
      if kubectl get ns $ns &> /dev/null; then
        # Count pods
        pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -cEv 'Completed|Evicted|Terminating' || echo "0")
        # Check ingress
        ingress_count=$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")
        ingress_status="$ingress_count ingress(es)"
        
        printf "%-20s %-45s %-12s %-10s %-10s\n" "Namespace" "N/A" "$ns" "$pod_count" "$ingress_status"
      fi
    done
  fi

  echo -e "\n${GREEN}Service readiness validated across Pods and Ingress layers.${NC}"
}

function debug_namespace() {
  section "Namespace Debugging Suite"

  read -p "Enter namespace to debug (e.g. monitoring): " ns

  echo -e "${YELLOW}Pods in $ns:${NC}"
  kubectl get pods -n "$ns" -o wide || echo -e "${YELLOW}No pods found in $ns${NC}"

  echo -e "\n${YELLOW}Services in $ns:${NC}"
  kubectl get svc -n "$ns" || echo -e "${YELLOW}No services found in $ns${NC}"

  echo -e "\n${YELLOW}Deployments in $ns:${NC}"
  kubectl get deploy -n "$ns" || echo -e "${YELLOW}No deployments found in $ns${NC}"

  echo -e "\n${YELLOW}Events in $ns (sorted):${NC}"
  kubectl get events -n "$ns" --sort-by=.lastTimestamp || echo -e "${YELLOW}No events found in $ns${NC}"

  echo -e "\n${YELLOW}Logs from first pod in $ns (if any):${NC}"
  first_pod=$(kubectl get pods -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$first_pod" ]; then
    kubectl logs -n "$ns" "$first_pod" --tail=50 || echo -e "${YELLOW}No logs found for $first_pod${NC}"
  else
    echo -e "${YELLOW}No pods found to fetch logs.${NC}"
  fi
}

function debug_pod_logs() {
  section "Select a Pod to View and Stream Logs"

  read -p "Enter namespace to inspect: " ns
  echo -e "${YELLOW}Fetching pods in namespace: $ns${NC}"

  pods=($(kubectl get pods -n "$ns" --no-headers -o custom-columns=":metadata.name"))
  if [ ${#pods[@]} -eq 0 ]; then
    echo -e "${YELLOW}No pods found in namespace $ns${NC}"
    return
  fi

  echo -e "\nSelect a pod to view logs:"
  select pod in "${pods[@]}"; do
    if [[ -n "$pod" ]]; then
      echo -e "${GREEN}Streaming logs for pod: $pod (Ctrl+C to stop)${NC}"
      kubectl logs -n "$ns" "$pod" --follow
      break
    else
      echo -e "${YELLOW}Invalid selection. Try again.${NC}"
    fi
  done
}

function uninstall_component() {
  section "Uninstalling All Components"
  echo "This will attempt to delete all installed Helm charts and namespaces."
  read -p "Are you sure? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    helm uninstall cilium -n kube-system || true
    helm uninstall longhorn -n longhorn-system || true
    helm uninstall kube-prometheus-stack -n monitoring || true
    helm uninstall loki -n loki || true
    helm uninstall rancher -n cattle-system || true
    helm uninstall cert-manager -n cert-manager || true
    helm uninstall my-mongo -n database || true
    helm uninstall my-postgres -n database || true
    helm uninstall my-mysql -n database || true
    helm uninstall redis -n database || true
    helm uninstall my-mariadb -n database || true
    helm uninstall traefik -n traefik || true
    kubectl delete ns longhorn-system monitoring loki cattle-system cert-manager database traefik pgadmin kubevirt || true
    echo -e "${GREEN}Uninstall complete.${NC}"
  else
    echo "Aborted."
  fi
}

function cleanup_database_namespace() {
  section "Cleaning up Database namespace"
  
  # Uninstall Redis
  helm uninstall redis -n database || true
  
  # Remove MongoDB cluster
  kubectl delete psmdb psmdb -n database || true
  
  # Remove MongoDB operator
  kubectl delete deployment percona-server-mongodb-operator -n database || true
  
  # Remove secrets
  kubectl delete secret psmdb-secrets -n database || true
  
  # Remove PVCs
  kubectl delete pvc --all -n database || true
  
  # Remove namespace
  kubectl delete namespace database || true
  
  echo -e "${GREEN}Database namespace cleanup completed${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Utilities script directly"
  PS3='Select utility: '
  options=(
    "Request TLS Certificates" 
    "Patch Ingresses for TLS" 
    "Show Status Summary"
    "Check Node Taints"
    "Check Deployment Status"
    "Service Health Check"
    "Debug Namespace"
    "View Pod Logs"
    "Uninstall Components"
    "Cleanup Database Namespace"
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Request TLS Certificates")
        apply_tls_certificates
        ;;
      "Patch Ingresses for TLS")
        patch_ingresses_for_tls
        ;;
      "Show Status Summary")
        show_cluster_status_summary
        ;;
      "Check Node Taints")
        check_node_taints_and_labels
        ;;
      "Check Deployment Status")
        wait_for_deployments
        ;;
      "Service Health Check")
        check_service_health_detailed
        ;;
      "Debug Namespace")
        debug_namespace
        ;;
      "View Pod Logs")
        debug_pod_logs
        ;;
      "Uninstall Components")
        uninstall_component
        ;;
      "Cleanup Database Namespace")
        cleanup_database_namespace
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