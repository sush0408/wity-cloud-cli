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

function install_monitoring() {
  section "Installing Prometheus + Grafana"
  
  # Ensure PATH includes RKE2 binaries
  export PATH=$PATH:/var/lib/rancher/rke2/bin
  
  # Set KUBECONFIG if not already set
  if [[ -z "$KUBECONFIG" ]]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  fi
  
  # Verify kubectl works
  if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    echo -e "${YELLOW}Checking RKE2 status...${NC}"
    systemctl status rke2-server --no-pager -l
    return 1
  fi
  
  # Update helm repos
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
  helm repo update
  
  # Use safe installation
  safe_helm_install "kube-prometheus-stack" "prometheus-community/kube-prometheus-stack" "monitoring" \
    --version 55.5.0 \
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
    --set grafana.persistence.enabled=true \
    --set grafana.persistence.size=5Gi \
    --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
    --set kubeEtcd.enabled=false \
    --set kubeControllerManager.enabled=false \
    --set kubeScheduler.enabled=false \
    --timeout 10m \
    --wait
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Prometheus and Grafana monitoring stack installed successfully${NC}"
    
    # Automatically set up Grafana ingress
    echo -e "${YELLOW}Setting up Grafana ingress for external access...${NC}"
    setup_grafana_ingress
    
    # Check if Loki is installed and configure it as a datasource
    if kubectl get namespace loki &>/dev/null && kubectl get service loki -n loki &>/dev/null; then
      echo -e "${YELLOW}Loki detected - configuring as Grafana datasource...${NC}"
      configure_loki_datasource
    else
      echo -e "${YELLOW}Loki not found. Install Loki first, then run 'configure_loki_datasource' to add it to Grafana.${NC}"
    fi
    
    echo -e "${YELLOW}Access Grafana through Rancher or by setting up ingress rules${NC}"
    echo -e "${YELLOW}Default Grafana credentials: admin/prom-operator${NC}"
    
    # Show service information
    echo -e "\n${YELLOW}Services created:${NC}"
    kubectl get svc -n monitoring
    
    # Show how to access Grafana
    echo -e "\n${YELLOW}To access Grafana locally via port-forward:${NC}"
    echo -e "kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    echo -e "Then visit: http://localhost:3000"
  else
    echo -e "${RED}Failed to install monitoring stack${NC}"
    return 1
  fi
}

function install_loki() {
  section "Installing Loki + Promtail"
  
  # Ensure PATH includes RKE2 binaries
  export PATH=$PATH:/var/lib/rancher/rke2/bin
  
  # Set KUBECONFIG if not already set
  if [[ -z "$KUBECONFIG" ]]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
  fi
  
  # Add Grafana helm repo
  helm repo add grafana https://grafana.github.io/helm-charts || true
  helm repo update
  
  # Use safe installation
  safe_helm_install "loki" "grafana/loki-stack" "loki" \
    --version 2.10.2 \
    --set loki.enabled=true \
    --set promtail.enabled=true \
    --set grafana.enabled=false \
    --set prometheus.enabled=false \
    --set loki.persistence.enabled=true \
    --set loki.persistence.size=10Gi \
    --timeout 10m \
    --wait
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Loki log aggregation system installed successfully${NC}"
    
    # Automatically set up Loki ingress
    echo -e "${YELLOW}Setting up Loki ingress for external access...${NC}"
    setup_loki_ingress
    
    # Check if Grafana is installed and configure Loki as a datasource
    if kubectl get namespace monitoring &>/dev/null && kubectl get service kube-prometheus-stack-grafana -n monitoring &>/dev/null; then
      echo -e "${YELLOW}Grafana detected - configuring Loki as datasource...${NC}"
      configure_loki_datasource
    else
      echo -e "${YELLOW}Grafana not found. Install Grafana first, then run 'configure_loki_datasource' to add Loki.${NC}"
    fi
    
    echo -e "${YELLOW}Configure Grafana to use Loki as a data source to view logs${NC}"
    echo -e "${YELLOW}Loki endpoint: http://loki.loki.svc.cluster.local:3100${NC}"
    
    # Show service information
    echo -e "\n${YELLOW}Services created:${NC}"
    kubectl get svc -n loki
  else
    echo -e "${RED}Failed to install Loki stack${NC}"
    return 1
  fi
}

function configure_loki_datasource() {
  section "Configuring Loki as Grafana Datasource"
  
  # Check if both Grafana and Loki are available
  if ! kubectl get service kube-prometheus-stack-grafana -n monitoring &>/dev/null; then
    echo -e "${RED}Grafana service not found in monitoring namespace${NC}"
    return 1
  fi
  
  if ! kubectl get service loki -n loki &>/dev/null; then
    echo -e "${RED}Loki service not found in loki namespace${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Creating Loki datasource configuration...${NC}"
  
  # Create a ConfigMap for Loki datasource
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-loki-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "1"
    app.kubernetes.io/instance: kube-prometheus-stack
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/part-of: kube-prometheus-stack
data:
  loki-datasource.yaml: |-
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      uid: loki
      url: http://loki.loki.svc.cluster.local:3100
      access: proxy
      isDefault: false
      jsonData:
        maxLines: 1000
        timeout: 60s
        httpMethod: GET
        manageAlerts: false
        alertmanagerUid: alertmanager
      editable: true
EOF
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Loki datasource ConfigMap created successfully${NC}"
    
    # Restart Grafana to pick up the new datasource
    echo -e "${YELLOW}Restarting Grafana to load Loki datasource...${NC}"
    kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
    
    # Wait for Grafana to be ready
    echo -e "${YELLOW}Waiting for Grafana to restart...${NC}"
    kubectl rollout status deployment kube-prometheus-stack-grafana -n monitoring --timeout=120s
    
    if [[ $? -eq 0 ]]; then
      echo -e "${GREEN}✅ Loki datasource configured successfully in Grafana!${NC}"
      echo -e "${YELLOW}📋 Datasource Details:${NC}"
      echo -e "  - Name: Loki"
      echo -e "  - Type: loki"
      echo -e "  - URL: http://loki.loki.svc.cluster.local:3100"
      echo -e "  - Max Lines: 1000"
      echo -e "  - Timeout: 60s"
      echo ""
      echo -e "${YELLOW}🔍 How to use Loki in Grafana:${NC}"
      echo -e "  1. Go to Grafana → Explore"
      echo -e "  2. Select 'Loki' from the datasource dropdown"
      echo -e "  3. Try these LogQL queries:"
      echo -e "     • {job=~\".+\"} - All logs"
      echo -e "     • {namespace=\"monitoring\"} - Monitoring namespace logs"
      echo -e "     • {job=\"pgadmin/pgadmin\"} - PgAdmin logs"
      echo -e "     • {job=~\".+\"} |= \"error\" - Error logs"
      echo ""
      echo -e "${YELLOW}⚠️  Note: Health check may show errors (this is normal)${NC}"
      echo -e "  The error 'parse error: unexpected IDENTIFIER' is a known Grafana issue"
      echo -e "  with Loki health checks. It doesn't affect functionality."
    else
      echo -e "${RED}Failed to restart Grafana${NC}"
      return 1
    fi
  else
    echo -e "${RED}Failed to create Loki datasource ConfigMap${NC}"
    return 1
  fi
}

function remove_loki_datasource() {
  section "Removing Loki Datasource from Grafana"
  
  echo -e "${YELLOW}Removing Loki datasource ConfigMap...${NC}"
  kubectl delete configmap grafana-loki-datasource -n monitoring --ignore-not-found=true
  
  echo -e "${YELLOW}Restarting Grafana to remove Loki datasource...${NC}"
  kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
  kubectl rollout status deployment kube-prometheus-stack-grafana -n monitoring --timeout=120s
  
  echo -e "${GREEN}Loki datasource removed from Grafana${NC}"
}

function setup_grafana_ingress() {
  section "Setting up Grafana Ingress"
  
  # Get node IP for nip.io domain
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Check if ingress already exists and has HTTPS redirect issues
  if kubectl get ingress grafana-ingress -n monitoring &>/dev/null; then
    echo -e "${YELLOW}Found existing Grafana ingress. Checking configuration...${NC}"
    
    # Check for problematic middleware
    MIDDLEWARE=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.metadata.annotations.traefik\.ingress\.kubernetes\.io/router\.middlewares}' 2>/dev/null || echo "")
    
    if [[ "$MIDDLEWARE" == *"redirect-https"* ]]; then
      echo -e "${YELLOW}Found HTTPS redirect middleware. Removing...${NC}"
      kubectl patch ingress grafana-ingress -n monitoring --type='json' -p='[{"op": "remove", "path": "/metadata/annotations/traefik.ingress.kubernetes.io~1router.middlewares"}]'
    fi
    
    # Remove TLS configuration if it exists
    TLS=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.spec.tls}' 2>/dev/null)
    if [[ -n "$TLS" && "$TLS" != "null" ]]; then
      echo -e "${YELLOW}Removing TLS configuration to prevent HTTPS issues...${NC}"
      kubectl patch ingress grafana-ingress -n monitoring --type='json' -p='[{"op": "remove", "path": "/spec/tls"}]' 2>/dev/null || true
    fi
    
    # Clean up any failed certificate attempts
    echo -e "${YELLOW}Cleaning up failed certificates...${NC}"
    kubectl delete certificate grafana-tls -n monitoring --ignore-not-found=true
    kubectl delete certificaterequest grafana-tls-1 -n monitoring --ignore-not-found=true
    kubectl delete secret grafana-tls-secret -n monitoring --ignore-not-found=true
    kubectl delete ingress -n monitoring -l acme.cert-manager.io/http01-solver=true --ignore-not-found=true
    
    # Check if dev.tese.io host exists
    HOSTS=$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.spec.rules[*].host}')
    if [[ "$HOSTS" != *"grafana.dev.tese.io"* ]]; then
      echo -e "${YELLOW}Adding dev.tese.io domain to existing ingress...${NC}"
      kubectl patch ingress grafana-ingress -n monitoring --type='json' -p="[{
        \"op\": \"add\",
        \"path\": \"/spec/rules/-\",
        \"value\": {
          \"host\": \"grafana.dev.tese.io\",
          \"http\": {
            \"paths\": [{
              \"path\": \"/\",
              \"pathType\": \"Prefix\",
              \"backend\": {
                \"service\": {
                  \"name\": \"kube-prometheus-stack-grafana\",
                  \"port\": {
                    \"number\": 80
                  }
                }
              }
            }]
          }
        }
      }]"
    fi
    
    echo -e "${GREEN}Grafana ingress updated with dual domain support${NC}"
  else
    echo -e "${YELLOW}Creating new Grafana ingress with dual domain support...${NC}"
    
    # Create ingress with both domains from the start
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: grafana.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
  - host: grafana.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
EOF
    echo -e "${GREEN}Grafana ingress created with dual domain support${NC}"
  fi
  
  echo -e "${YELLOW}Grafana Access URLs:${NC}"
  echo -e "  - Local:  http://grafana.${NODE_IP}.nip.io"
  echo -e "  - Public: http://grafana.dev.tese.io (requires Route53 setup)"
  echo -e "${YELLOW}Default credentials: admin/prom-operator${NC}"
}

function setup_prometheus_ingress() {
  section "Setting up Prometheus Ingress"
  
  # Get node IP for nip.io domain
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Check if ingress already exists
  if kubectl get ingress prometheus-ingress -n monitoring &>/dev/null; then
    echo -e "${YELLOW}Found existing Prometheus ingress. Updating...${NC}"
    
    # Clean up any TLS configuration
    kubectl patch ingress prometheus-ingress -n monitoring --type='json' -p='[{"op": "remove", "path": "/spec/tls"}]' 2>/dev/null || true
    kubectl patch ingress prometheus-ingress -n monitoring --type='json' -p='[{"op": "remove", "path": "/metadata/annotations/traefik.ingress.kubernetes.io~1router.middlewares"}]' 2>/dev/null || true
    
    # Add dev.tese.io domain if missing
    HOSTS=$(kubectl get ingress prometheus-ingress -n monitoring -o jsonpath='{.spec.rules[*].host}')
    if [[ "$HOSTS" != *"prometheus.dev.tese.io"* ]]; then
      kubectl patch ingress prometheus-ingress -n monitoring --type='json' -p="[{
        \"op\": \"add\",
        \"path\": \"/spec/rules/-\",
        \"value\": {
          \"host\": \"prometheus.dev.tese.io\",
          \"http\": {
            \"paths\": [{
              \"path\": \"/\",
              \"pathType\": \"Prefix\",
              \"backend\": {
                \"service\": {
                  \"name\": \"kube-prometheus-stack-prometheus\",
                  \"port\": {
                    \"number\": 9090
                  }
                }
              }
            }]
          }
        }
      }]"
    fi
  else
    # Create ingress with both domains
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus-ingress
  namespace: monitoring
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: prometheus.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-prometheus
            port:
              number: 9090
  - host: prometheus.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-prometheus
            port:
              number: 9090
EOF
  fi

  echo -e "${GREEN}Prometheus ingress created/updated${NC}"
  echo -e "${YELLOW}Prometheus Access URLs:${NC}"
  echo -e "  - Local:  http://prometheus.${NODE_IP}.nip.io"
  echo -e "  - Public: http://prometheus.dev.tese.io (requires Route53 setup)"
}

function setup_loki_ingress() {
  section "Setting up Loki Ingress"
  
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Create ingress for Loki in the correct namespace
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: loki-ingress
  namespace: loki
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: loki.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki
            port:
              number: 3100
  - host: loki.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki
            port:
              number: 3100
EOF

  echo -e "${GREEN}Loki ingress created${NC}"
  echo -e "${YELLOW}Loki Access URLs:${NC}"
  echo -e "  - Local:  http://loki.${NODE_IP}.nip.io"
  echo -e "  - Public: http://loki.dev.tese.io (requires Route53 setup)"
}

function cleanup_failed_certificates() {
  section "Cleaning up failed certificates and ACME challenges"
  
  echo -e "${YELLOW}Removing failed certificates...${NC}"
  kubectl get certificates --all-namespaces | grep -v "True" | grep -v "NAME" | while read namespace name ready secret age; do
    if [[ "$ready" == "False" ]]; then
      echo "  Removing failed certificate: $name in namespace $namespace"
      kubectl delete certificate "$name" -n "$namespace" --ignore-not-found=true
    fi
  done
  
  echo -e "${YELLOW}Removing failed certificate requests...${NC}"
  kubectl get certificaterequests --all-namespaces | grep -v "True" | grep -v "NAME" | while read namespace name approved denied ready issuer requestor age; do
    if [[ "$ready" == "False" ]]; then
      echo "  Removing failed certificate request: $name in namespace $namespace"
      kubectl delete certificaterequest "$name" -n "$namespace" --ignore-not-found=true
    fi
  done
  
  echo -e "${YELLOW}Removing ACME solver ingresses...${NC}"
  kubectl delete ingress --all-namespaces -l acme.cert-manager.io/http01-solver=true --ignore-not-found=true
  
  echo -e "${GREEN}Certificate cleanup completed${NC}"
}

function check_monitoring_status() {
  section "Checking Monitoring Stack Status"
  
  echo -e "${YELLOW}Monitoring namespace pods:${NC}"
  kubectl get pods -n monitoring
  
  echo -e "\n${YELLOW}Monitoring services:${NC}"
  kubectl get svc -n monitoring
  
  echo -e "\n${YELLOW}Loki namespace pods:${NC}"
  kubectl get pods -n loki 2>/dev/null || echo "Loki not installed"
  
  echo -e "\n${YELLOW}Loki services:${NC}"
  kubectl get svc -n loki 2>/dev/null || echo "Loki not installed"
  
  echo -e "\n${YELLOW}Persistent Volume Claims:${NC}"
  kubectl get pvc -n monitoring
  kubectl get pvc -n loki 2>/dev/null || echo "No Loki PVCs"
  
  echo -e "\n${YELLOW}Grafana Datasources Configuration:${NC}"
  if kubectl get configmap -n monitoring | grep -q "grafana.*datasource"; then
    echo "Found Grafana datasource ConfigMaps:"
    kubectl get configmap -n monitoring | grep "grafana.*datasource"
    
    # Check if Loki datasource is configured
    if kubectl get configmap grafana-loki-datasource -n monitoring &>/dev/null; then
      echo -e "${GREEN}✅ Loki datasource is configured${NC}"
    else
      echo -e "${YELLOW}⚠️  Loki datasource not configured${NC}"
      echo -e "   Run: ./monitoring.sh and select 'Configure Loki Datasource in Grafana'"
    fi
  else
    echo "No Grafana datasource ConfigMaps found"
  fi
  
  echo -e "\n${YELLOW}Ingress Status:${NC}"
  kubectl get ingress -n monitoring 2>/dev/null || echo "No ingresses in monitoring namespace"
  kubectl get ingress -n loki 2>/dev/null || echo "No ingresses in loki namespace"
  
  # Test Loki connectivity if available
  if kubectl get service loki -n loki &>/dev/null; then
    echo -e "\n${YELLOW}Testing Loki connectivity:${NC}"
    
    # Test internal connectivity
    LOKI_POD=$(kubectl get pods -n loki -l app=loki --no-headers | head -1 | awk '{print $1}')
    if [[ -n "$LOKI_POD" ]]; then
      echo -n "  Internal API test: "
      if kubectl exec -n loki "$LOKI_POD" -- wget -q -O- http://localhost:3100/ready 2>/dev/null | grep -q "ready"; then
        echo -e "${GREEN}✅ Ready${NC}"
      else
        echo -e "${RED}❌ Failed${NC}"
      fi
    fi
    
    # Test external connectivity if ingress exists
    if kubectl get ingress loki-ingress -n loki &>/dev/null; then
      NODE_IP=$(hostname -I | awk '{print $1}')
      echo -n "  External API test: "
      if curl -s --connect-timeout 5 "http://loki.${NODE_IP}.nip.io/ready" 2>/dev/null | grep -q "ready"; then
        echo -e "${GREEN}✅ Ready${NC}"
      else
        echo -e "${RED}❌ Failed${NC}"
      fi
    fi
  fi
  
  echo -e "\n${YELLOW}Quick Access URLs:${NC}"
  NODE_IP=$(hostname -I | awk '{print $1}')
  echo -e "  Grafana:    http://grafana.${NODE_IP}.nip.io (admin/prom-operator)"
  echo -e "  Prometheus: http://prometheus.${NODE_IP}.nip.io"
  if kubectl get service loki -n loki &>/dev/null; then
    echo -e "  Loki:       http://loki.${NODE_IP}.nip.io"
  fi
  
  echo -e "\n${YELLOW}Troubleshooting Tips:${NC}"
  echo -e "  • If Loki health check shows errors in Grafana, this is normal"
  echo -e "  • Use LogQL queries like: {job=~\".+\"} or {namespace=\"monitoring\"}"
  echo -e "  • Avoid empty-compatible matchers like {job=~\".*\"}"
  echo -e "  • Check logs: kubectl logs -n loki -l app=loki"
  echo -e "  • Check Promtail: kubectl logs -n loki -l app=promtail"
}

function install_pmm_server() {
  section "Installing PMM (Percona Monitoring and Management) Server"
  
  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    return 1
  fi

  local MONITORING_NAMESPACE="monitoring"
  
  # Create monitoring namespace if it doesn't exist
  if ! namespace_exists "$MONITORING_NAMESPACE"; then
    echo "Creating monitoring namespace..."
    kubectl create namespace $MONITORING_NAMESPACE
  fi

  # Create PMM Server configuration directory
  mkdir -p monitoring/pmm

  # Check if PMM is already installed
  if kubectl get deployment pmm-server -n $MONITORING_NAMESPACE &>/dev/null; then
    if ask_approval "PMM Server is already installed. Do you want to reinstall it?"; then
      echo "Removing existing PMM Server..."
      kubectl delete deployment pmm-server -n $MONITORING_NAMESPACE || true
      kubectl delete service pmm-server -n $MONITORING_NAMESPACE || true
      kubectl delete pvc pmm-data -n $MONITORING_NAMESPACE || true
      kubectl delete secret pmm-secrets -n $MONITORING_NAMESPACE || true
      kubectl delete ingress pmm-ingress -n $MONITORING_NAMESPACE || true
      sleep 10
    else
      echo -e "${GREEN}Using existing PMM Server installation${NC}"
      return 0
    fi
  fi

  echo "Creating PMM Server configuration..."
  cat > monitoring/pmm/pmm-server.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pmm-data
  namespace: $MONITORING_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: longhorn
---
apiVersion: v1
kind: Secret
metadata:
  name: pmm-secrets
  namespace: $MONITORING_NAMESPACE
type: Opaque
data:
  PMM_ADMIN_PASSWORD: YWRtaW4tcGFzc3dvcmQ=  # admin-password
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pmm-server
  namespace: $MONITORING_NAMESPACE
  labels:
    app: pmm-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pmm-server
  template:
    metadata:
      labels:
        app: pmm-server
    spec:
      containers:
      - name: pmm-server
        image: percona/pmm-server:2
        ports:
        - containerPort: 80
          name: http
        - containerPort: 443
          name: https
        env:
        - name: PMM_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pmm-secrets
              key: PMM_ADMIN_PASSWORD
        volumeMounts:
        - name: pmm-data
          mountPath: /srv
        readinessProbe:
          httpGet:
            path: /ping
            port: 80
          initialDelaySeconds: 30
          timeoutSeconds: 5
        livenessProbe:
          httpGet:
            path: /ping
            port: 80
          initialDelaySeconds: 60
          timeoutSeconds: 5
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2000m
            memory: 4Gi
      volumes:
      - name: pmm-data
        persistentVolumeClaim:
          claimName: pmm-data
---
apiVersion: v1
kind: Service
metadata:
  name: pmm-server
  namespace: $MONITORING_NAMESPACE
  labels:
    app: pmm-server
spec:
  ports:
  - port: 80
    targetPort: 80
    name: http
  - port: 443
    targetPort: 443
    name: https
  selector:
    app: pmm-server
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pmm-ingress
  namespace: $MONITORING_NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: pmm.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pmm-server
            port:
              number: 80
EOF

  # Apply PMM server resources
  echo "Deploying PMM Server..."
  kubectl apply -f monitoring/pmm/pmm-server.yaml || {
    echo -e "${RED}Failed to deploy PMM Server${NC}"
    return 1
  }

  # Wait for PMM to be ready
  echo "Waiting for PMM Server to be ready..."
  if wait_for_deployment "pmm-server" "$MONITORING_NAMESPACE" 300; then
    echo -e "${GREEN}PMM Server is ready!${NC}"
    
    # Get PMM service details
    PMM_IP=$(kubectl get service pmm-server -n $MONITORING_NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$PMM_IP" ]; then
      echo -e "${GREEN}PMM Server is available at: http://$PMM_IP${NC}"
    fi
    
    echo -e "${GREEN}PMM Server deployment completed!${NC}"
    echo "=================================================="
    echo "PMM access details:"
    echo "  - Internal URL: http://pmm-server.$MONITORING_NAMESPACE.svc.cluster.local"
    echo "  - Username: admin"
    echo "  - Password: admin-password (change this in production!)"
    echo ""
    echo "To access PMM externally, run:"
    echo "  kubectl port-forward svc/pmm-server 8080:80 -n $MONITORING_NAMESPACE"
    echo "Then visit: http://localhost:8080"
    echo ""
    echo "To check PMM status:"
    echo "  kubectl get pods -n $MONITORING_NAMESPACE -l app=pmm-server"
    echo "  kubectl logs -n $MONITORING_NAMESPACE -l app=pmm-server"
    echo "=================================================="
  else
    echo -e "${RED}PMM Server failed to become ready${NC}"
    echo "Check the deployment status with:"
    echo "  kubectl get pods -n $MONITORING_NAMESPACE -l app=pmm-server"
    echo "  kubectl describe deployment pmm-server -n $MONITORING_NAMESPACE"
    return 1
  fi
}

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

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Monitoring script directly"
  PS3='Select monitoring component: '
  options=(
    "Prometheus + Grafana" 
    "Loki + Promtail" 
    "Configure Loki Datasource in Grafana"
    "Remove Loki Datasource from Grafana"
    "Setup Grafana Ingress"
    "Setup Prometheus Ingress"
    "Setup Loki Ingress"
    "Cleanup Failed Certificates"
    "Check Status"
    "All Monitoring Components" 
    "Install PMM Server"
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Prometheus + Grafana")
        install_monitoring
        ;;
      "Loki + Promtail")
        install_loki
        ;;
      "Configure Loki Datasource in Grafana")
        configure_loki_datasource
        ;;
      "Remove Loki Datasource from Grafana")
        remove_loki_datasource
        ;;
      "Setup Grafana Ingress")
        setup_grafana_ingress
        ;;
      "Setup Prometheus Ingress")
        setup_prometheus_ingress
        ;;
      "Setup Loki Ingress")
        setup_loki_ingress
        ;;
      "Cleanup Failed Certificates")
        cleanup_failed_certificates
        ;;
      "Check Status")
        check_monitoring_status
        ;;
      "All Monitoring Components")
        install_monitoring
        install_loki
        setup_prometheus_ingress
        break
        ;;
      "Install PMM Server")
        install_pmm_server
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