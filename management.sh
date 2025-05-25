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
  kubectl create namespace cert-manager || true
  helm install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.14.4 --set installCRDs=true
  
  echo -e "${GREEN}Cert Manager installed for TLS certificate automation${NC}"
}

function install_rancher() {
  section "Installing Rancher"
  NODE_IP=$(hostname -I | awk '{print $1}')
  kubectl create namespace cattle-system || true
  helm install rancher rancher-latest/rancher --namespace cattle-system \
    --set hostname=rancher.${NODE_IP}.nip.io \
    --set replicas=1
  
  echo -e "${GREEN}Rancher management UI installed${NC}"
  echo -e "${GREEN}Rancher available at: https://rancher.${NODE_IP}.nip.io${NC}"
}

function install_traefik_ingress() {
  section "Installing Traefik Ingress Controller"
  helm repo add traefik https://traefik.github.io/charts
  helm repo update
  kubectl create namespace traefik || true
  helm install traefik traefik/traefik --namespace traefik \
    --set service.type=LoadBalancer \
    --set ingressRoute.dashboard=true
  
  echo -e "${GREEN}Traefik ingress controller installed${NC}"
  echo -e "${YELLOW}Configure Traefik dashboard access by creating an IngressRoute${NC}"
}

function install_pgadmin() {
  section "Installing pgAdmin 4"
  kubectl create namespace pgadmin || true
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
      containers:
      - name: pgadmin
        image: dpage/pgadmin4
        ports:
        - containerPort: 80
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          value: admin@admin.com
        - name: PGADMIN_DEFAULT_PASSWORD
          value: admin
        volumeMounts:
        - name: pgadmin-storage
          mountPath: /var/lib/pgadmin
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
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pgadmin-ingress
  namespace: pgadmin
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
  - host: pgadmin.127.0.0.1.nip.io
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
  echo -e "${GREEN}pgAdmin deployed. Visit: http://pgadmin.127.0.0.1.nip.io${NC}"
  echo -e "${YELLOW}Login: admin@admin.com / admin${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Management script directly"
  PS3='Select management component: '
  options=("Cert Manager" "Rancher" "Traefik Ingress" "pgAdmin" "All Management Components" "Quit")
  
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