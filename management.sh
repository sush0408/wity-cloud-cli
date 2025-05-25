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

function install_cert_manager() {
  section "Installing cert-manager"
  
  # Use safe installation
  safe_helm_install "cert-manager" "jetstack/cert-manager" "cert-manager" \
    --version v1.14.4 \
    --set installCRDs=true
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Cert Manager installed for TLS certificate automation${NC}"
  fi
}

function install_rancher() {
  section "Installing Rancher"
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Use safe installation
  safe_helm_install "rancher" "rancher-latest/rancher" "cattle-system" \
    --set hostname=rancher.${NODE_IP}.nip.io \
    --set replicas=1
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Rancher management UI installed${NC}"
    
    # Automatically set up HTTP ingress for dual domain support
    echo -e "${YELLOW}Setting up Rancher HTTP ingress for dual domain access...${NC}"
    setup_rancher_ingress
    
    echo -e "${GREEN}Rancher available at: https://rancher.${NODE_IP}.nip.io${NC}"
  fi
}

function install_traefik_ingress() {
  section "Installing Traefik Ingress Controller"
  helm repo add traefik https://traefik.github.io/charts
  helm repo update
  
  # Use safe installation with corrected parameters
  safe_helm_install "traefik" "traefik/traefik" "traefik" \
    --set service.type=LoadBalancer \
    --set dashboard.enabled=true \
    --set dashboard.domain=traefik.local
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Traefik ingress controller installed${NC}"
    echo -e "${YELLOW}Access Traefik dashboard by setting up port-forward or ingress${NC}"
    echo -e "${YELLOW}Port-forward command: kubectl port-forward -n traefik svc/traefik 9000:9000${NC}"
  fi
}

function install_pgadmin() {
  section "Installing pgAdmin 4"
  
  # Check if pgAdmin is already deployed
  if kubectl get deployment pgadmin -n pgadmin &>/dev/null; then
    echo -e "${GREEN}pgAdmin is already deployed${NC}"
    
    # Check if it's running
    if kubectl get pods -n pgadmin | grep -q "Running" 2>/dev/null; then
      echo -e "${GREEN}pgAdmin is running properly${NC}"
      
      # Ensure ingress has dual domain support
      setup_pgadmin_ingress
      return 0
    else
      echo -e "${YELLOW}pgAdmin is deployed but may not be running properly${NC}"
      read -p "Do you want to redeploy pgAdmin? [y/N]: " redeploy
      if [[ ! "$redeploy" =~ ^[Yy]$ ]]; then
        return 0
      fi
      
      echo -e "${YELLOW}Removing existing pgAdmin deployment...${NC}"
      kubectl delete namespace pgadmin --ignore-not-found=true
      sleep 10
    fi
  fi
  
  # Check if namespace exists
  if namespace_exists "pgadmin"; then
    echo -e "${YELLOW}pgAdmin namespace exists but no deployment found${NC}"
    read -p "Do you want to clean up and reinstall? [y/N]: " cleanup
    if [[ "$cleanup" =~ ^[Yy]$ ]]; then
      kubectl delete namespace pgadmin --ignore-not-found=true
      sleep 10
    else
      echo -e "${YELLOW}Skipping pgAdmin installation${NC}"
      return 0
    fi
  fi
  
  NODE_IP=$(hostname -I | awk '{print $1}')
  kubectl create namespace pgadmin
  
  # Create improved pgAdmin deployment with proper permissions
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pgadmin-pvc
  namespace: pgadmin
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: pgadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgadmin
  template:
    metadata:
      labels:
        app: pgadmin
    spec:
      securityContext:
        runAsUser: 5050
        runAsGroup: 5050
        fsGroup: 5050
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        ports:
        - containerPort: 80
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: admin@admin.com
        - name: PGADMIN_DEFAULT_PASSWORD
          value: admin
        - name: PGADMIN_CONFIG_SERVER_MODE
          value: "False"
        - name: PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED
          value: "False"
        - name: PGADMIN_LISTEN_PORT
          value: "80"
        volumeMounts:
        - name: pgadmin-storage
          mountPath: /var/lib/pgadmin
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 5050
          runAsGroup: 5050
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /misc/ping
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /misc/ping
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 30
      volumes:
      - name: pgadmin-storage
        persistentVolumeClaim:
          claimName: pgadmin-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: pgadmin
spec:
  selector:
    app: pgadmin
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
EOF
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}pgAdmin deployed successfully${NC}"
    
    # Wait for deployment to be ready
    echo -e "${YELLOW}Waiting for pgAdmin to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/pgadmin -n pgadmin
    
    # Set up ingress with dual domain support
    setup_pgadmin_ingress
    
    echo -e "${GREEN}pgAdmin is ready!${NC}"
    echo -e "${YELLOW}Login: admin@admin.com / admin${NC}"
  else
    echo -e "${RED}Failed to deploy pgAdmin${NC}"
    return 1
  fi
}

function setup_pgadmin_ingress() {
  section "Setting up pgAdmin Ingress"
  
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Remove any existing problematic ingress
  kubectl delete ingress pgadmin-ingress -n pgadmin --ignore-not-found=true
  
  # Clean up any failed certificates
  kubectl delete certificate pgadmin-tls -n pgadmin --ignore-not-found=true
  kubectl delete certificaterequest pgadmin-tls-1 -n pgadmin --ignore-not-found=true
  kubectl delete secret pgadmin-tls-secret -n pgadmin --ignore-not-found=true
  
  # Create clean ingress with dual domain support
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pgadmin-ingress
  namespace: pgadmin
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: pgadmin.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
  - host: pgadmin.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
EOF

  echo -e "${GREEN}pgAdmin ingress created with dual domain support${NC}"
  echo -e "${YELLOW}pgAdmin Access URLs:${NC}"
  echo -e "  - Local:  http://pgadmin.${NODE_IP}.nip.io"
  echo -e "  - Public: http://pgadmin.dev.tese.io (requires Route53 setup)"
}

function setup_rancher_ingress() {
  section "Setting up Rancher Ingress with dual domain support"
  
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Check if rancher-ingress exists (for nip.io access)
  if ! kubectl get ingress rancher-ingress -n cattle-system &>/dev/null; then
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rancher-ingress
  namespace: cattle-system
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: rancher.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rancher
            port:
              number: 80
  - host: rancher.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rancher
            port:
              number: 80
EOF
    
    echo -e "${GREEN}Rancher HTTP ingress created${NC}"
    echo -e "${YELLOW}Rancher Access URLs:${NC}"
    echo -e "  - Local:  http://rancher.${NODE_IP}.nip.io"
    echo -e "  - Public: http://rancher.dev.tese.io (requires Route53 setup)"
    echo -e "  - HTTPS:  https://rancher.${NODE_IP}.nip.io (original)"
  else
    echo -e "${GREEN}Rancher ingress already exists${NC}"
  fi
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Management script directly"
  PS3='Select management component: '
  options=(
    "Cert Manager" 
    "Rancher" 
    "Traefik Ingress" 
    "pgAdmin" 
    "Setup pgAdmin Ingress"
    "Setup Rancher Ingress"
    "All Management Components" 
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Cert Manager")
        install_cert_manager
        ;;
      "Rancher")
        install_rancher
        ;;
      "Traefik Ingress")
        install_traefik_ingress
        ;;
      "pgAdmin")
        install_pgadmin
        ;;
      "Setup pgAdmin Ingress")
        setup_pgadmin_ingress
        ;;
      "Setup Rancher Ingress")
        setup_rancher_ingress
        ;;
      "All Management Components")
        install_cert_manager
        install_rancher
        install_traefik_ingress
        install_pgadmin
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