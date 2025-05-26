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

# Function to ask for approval (interactive mode)
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

function install_argocd() {
  section "Installing ArgoCD"
  
  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    return 1
  fi

  local ARGOCD_NAMESPACE="argocd"
  
  # Create argocd namespace if it doesn't exist
  if ! namespace_exists "$ARGOCD_NAMESPACE"; then
    echo -e "${YELLOW}Creating argocd namespace...${NC}"
    kubectl create namespace $ARGOCD_NAMESPACE
    echo -e "${GREEN}Created namespace '$ARGOCD_NAMESPACE'${NC}"
  else
    echo -e "${GREEN}Namespace '$ARGOCD_NAMESPACE' already exists${NC}"
  fi

  # Check if ArgoCD is already installed
  if kubectl get deployment argocd-server -n $ARGOCD_NAMESPACE &>/dev/null; then
    if ask_approval "ArgoCD is already installed. Do you want to reinstall it?"; then
      echo "Removing existing ArgoCD..."
      kubectl delete namespace $ARGOCD_NAMESPACE --timeout=120s || true
      sleep 10
      kubectl create namespace $ARGOCD_NAMESPACE
    else
      echo -e "${GREEN}Using existing ArgoCD installation${NC}"
      show_argocd_info
      return 0
    fi
  fi

  # Install ArgoCD using the stable release
  echo -e "${YELLOW}Installing ArgoCD...${NC}"
  kubectl apply -n $ARGOCD_NAMESPACE -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  # Wait for ArgoCD to be ready
  echo -e "${YELLOW}Waiting for ArgoCD to be ready...${NC}"
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n $ARGOCD_NAMESPACE || {
    echo -e "${RED}ArgoCD server failed to become ready${NC}"
    return 1
  }

  # Patch ArgoCD server to disable TLS (for easier access)
  echo -e "${YELLOW}Configuring ArgoCD server...${NC}"
  kubectl patch deployment argocd-server -n $ARGOCD_NAMESPACE -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--insecure"}]' --type json

  # Wait for the patched deployment to be ready
  kubectl rollout status deployment/argocd-server -n $ARGOCD_NAMESPACE --timeout=120s

  # Create ArgoCD ingress
  setup_argocd_ingress

  # Show ArgoCD information
  show_argocd_info

  echo -e "${GREEN}✅ ArgoCD installation completed!${NC}"
}

function setup_argocd_ingress() {
  section "Setting up ArgoCD Ingress"
  
  local ARGOCD_NAMESPACE="argocd"
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # First, configure ArgoCD to run in insecure mode (HTTP)
  echo -e "${YELLOW}Configuring ArgoCD for insecure mode...${NC}"
  kubectl patch configmap argocd-cmd-params-cm -n $ARGOCD_NAMESPACE --type merge -p='{"data":{"server.insecure":"true"}}'
  
  # Restart ArgoCD server to apply the insecure mode
  kubectl rollout restart deployment/argocd-server -n $ARGOCD_NAMESPACE
  kubectl rollout status deployment/argocd-server -n $ARGOCD_NAMESPACE --timeout=120s
  
  # Create ingress for ArgoCD using traefik ingress controller
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: $ARGOCD_NAMESPACE
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: argocd.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
  - host: argocd.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

  echo -e "${GREEN}ArgoCD ingress created${NC}"
  echo -e "${YELLOW}ArgoCD Access URLs:${NC}"
  echo -e "  - Local:  http://argocd.${NODE_IP}.nip.io"
  echo -e "  - Public: http://argocd.dev.tese.io (requires Route53 setup)"
}

function show_argocd_info() {
  local ARGOCD_NAMESPACE="argocd"
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  echo -e "\n${YELLOW}ArgoCD Information:${NC}"
  echo -e "${YELLOW}Deployment Status:${NC}"
  kubectl get deployment -n $ARGOCD_NAMESPACE
  
  echo -e "\n${YELLOW}Service Status:${NC}"
  kubectl get svc -n $ARGOCD_NAMESPACE
  
  echo -e "\n${YELLOW}Access Information:${NC}"
  echo -e "  - Web UI: http://argocd.${NODE_IP}.nip.io"
  echo -e "  - Username: admin"
  
  # Get ArgoCD admin password
  local admin_password=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
  if [[ -n "$admin_password" ]]; then
    echo -e "  - Password: $admin_password"
  else
    echo -e "  - Password: Run 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d'"
  fi
  
  echo -e "\n${YELLOW}Port Forward Command:${NC}"
  echo -e "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:80"
  echo -e "  Then visit: http://localhost:8080"
}

function create_sample_application() {
  section "Creating Sample ArgoCD Application"
  
  local ARGOCD_NAMESPACE="argocd"
  
  # Create a sample application directory structure
  mkdir -p cicd/applications/sample-app/manifests
  
  # Create a sample deployment
  cat > cicd/applications/sample-app/manifests/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: sample-app
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
  namespace: default
spec:
  selector:
    app: sample-app
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

  # Create ArgoCD Application
  cat > cicd/applications/sample-app-argocd.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: $ARGOCD_NAMESPACE
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-username/your-repo.git
    targetRevision: HEAD
    path: cicd/applications/sample-app/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

  echo -e "${GREEN}✅ Sample application configuration created${NC}"
  echo -e "${YELLOW}Files created:${NC}"
  echo -e "  - cicd/applications/sample-app/manifests/deployment.yaml"
  echo -e "  - cicd/applications/sample-app-argocd.yaml"
  echo -e "\n${YELLOW}To deploy the sample application:${NC}"
  echo -e "  1. Push these files to your Git repository"
  echo -e "  2. Update the repoURL in sample-app-argocd.yaml"
  echo -e "  3. Apply: kubectl apply -f cicd/applications/sample-app-argocd.yaml"
}

function install_argocd_cli() {
  section "Installing ArgoCD CLI"
  
  # Check if argocd CLI is already installed
  if command -v argocd &> /dev/null; then
    echo -e "${GREEN}ArgoCD CLI is already installed${NC}"
    argocd version --client
    return 0
  fi
  
  echo -e "${YELLOW}Installing ArgoCD CLI...${NC}"
  
  # Download and install ArgoCD CLI
  local ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep tag_name | cut -d '"' -f 4)
  
  if [[ -z "$ARGOCD_VERSION" ]]; then
    echo -e "${RED}Failed to get ArgoCD version${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Downloading ArgoCD CLI version $ARGOCD_VERSION...${NC}"
  
  curl -sSL -o argocd-linux-amd64 "https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64"
  
  if [[ $? -eq 0 ]]; then
    chmod +x argocd-linux-amd64
    sudo mv argocd-linux-amd64 /usr/local/bin/argocd
    echo -e "${GREEN}✅ ArgoCD CLI installed successfully${NC}"
    argocd version --client
  else
    echo -e "${RED}Failed to download ArgoCD CLI${NC}"
    return 1
  fi
}

function setup_argocd_projects() {
  section "Setting up ArgoCD Projects"
  
  local ARGOCD_NAMESPACE="argocd"
  
  # Create projects directory
  mkdir -p cicd/projects
  
  # Create development project
  cat > cicd/projects/development-project.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: development
  namespace: $ARGOCD_NAMESPACE
spec:
  description: Development environment project
  sourceRepos:
  - '*'
  destinations:
  - namespace: 'dev-*'
    server: https://kubernetes.default.svc
  - namespace: default
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRole
  - group: 'rbac.authorization.k8s.io'
    kind: ClusterRoleBinding
  namespaceResourceWhitelist:
  - group: ''
    kind: '*'
  - group: 'apps'
    kind: '*'
  - group: 'networking.k8s.io'
    kind: '*'
  roles:
  - name: developer
    description: Developer role for development project
    policies:
    - p, proj:development:developer, applications, get, development/*, allow
    - p, proj:development:developer, applications, sync, development/*, allow
    - p, proj:development:developer, applications, action/*, development/*, allow
    - p, proj:development:developer, repositories, get, *, allow
    groups:
    - developers
EOF

  # Create production project
  cat > cicd/projects/production-project.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: $ARGOCD_NAMESPACE
spec:
  description: Production environment project
  sourceRepos:
  - 'https://github.com/your-org/production-configs.git'
  destinations:
  - namespace: 'prod-*'
    server: https://kubernetes.default.svc
  - namespace: database
    server: https://kubernetes.default.svc
  - namespace: monitoring
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  namespaceResourceWhitelist:
  - group: ''
    kind: '*'
  - group: 'apps'
    kind: '*'
  - group: 'networking.k8s.io'
    kind: '*'
  - group: 'psmdb.percona.com'
    kind: '*'
  roles:
  - name: admin
    description: Admin role for production project
    policies:
    - p, proj:production:admin, applications, *, production/*, allow
    - p, proj:production:admin, repositories, *, *, allow
    groups:
    - admins
  syncWindows:
  - kind: allow
    schedule: '0 9-17 * * MON-FRI'
    duration: 8h
    applications:
    - '*'
    manualSync: true
  - kind: deny
    schedule: '0 0-8,18-23 * * *'
    duration: 10h
    applications:
    - '*'
    manualSync: false
EOF

  # Apply the projects
  if ask_approval "Do you want to apply the ArgoCD projects?"; then
    kubectl apply -f cicd/projects/development-project.yaml
    kubectl apply -f cicd/projects/production-project.yaml
    echo -e "${GREEN}✅ ArgoCD projects created${NC}"
  fi
  
  echo -e "${YELLOW}Project files created:${NC}"
  echo -e "  - cicd/projects/development-project.yaml"
  echo -e "  - cicd/projects/production-project.yaml"
}

function create_mongodb_application() {
  section "Creating MongoDB ArgoCD Application"
  
  local ARGOCD_NAMESPACE="argocd"
  
  # Create MongoDB application directory
  mkdir -p cicd/applications/mongodb
  
  # Copy existing MongoDB configurations
  cp -r databases/mongodb/database-namespace/* cicd/applications/mongodb/ 2>/dev/null || true
  
  # Create ArgoCD Application for MongoDB
  cat > cicd/applications/mongodb-argocd.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mongodb-cluster
  namespace: $ARGOCD_NAMESPACE
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: production
  source:
    repoURL: https://github.com/your-username/your-repo.git
    targetRevision: HEAD
    path: cicd/applications/mongodb
  destination:
    server: https://kubernetes.default.svc
    namespace: database
  syncPolicy:
    automated:
      prune: false  # Don't auto-prune database resources
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - RespectIgnoreDifferences=true
  ignoreDifferences:
  - group: psmdb.percona.com
    kind: PerconaServerMongoDB
    jsonPointers:
    - /status
EOF

  echo -e "${GREEN}✅ MongoDB ArgoCD application configuration created${NC}"
  echo -e "${YELLOW}File created: cicd/applications/mongodb-argocd.yaml${NC}"
  echo -e "\n${YELLOW}To deploy MongoDB via ArgoCD:${NC}"
  echo -e "  1. Push the cicd/applications/mongodb/ directory to your Git repository"
  echo -e "  2. Update the repoURL in mongodb-argocd.yaml"
  echo -e "  3. Apply: kubectl apply -f cicd/applications/mongodb-argocd.yaml"
}

function create_monitoring_application() {
  section "Creating Monitoring ArgoCD Application"
  
  local ARGOCD_NAMESPACE="argocd"
  
  # Create monitoring application directory
  mkdir -p cicd/applications/monitoring/manifests
  
  # Copy existing monitoring configurations
  cp -r monitoring/* cicd/applications/monitoring/manifests/ 2>/dev/null || true
  
  # Create ArgoCD Application for Monitoring
  cat > cicd/applications/monitoring-argocd.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-stack
  namespace: $ARGOCD_NAMESPACE
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: production
  source:
    repoURL: https://github.com/your-username/your-repo.git
    targetRevision: HEAD
    path: cicd/applications/monitoring/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

  echo -e "${GREEN}✅ Monitoring ArgoCD application configuration created${NC}"
  echo -e "${YELLOW}File created: cicd/applications/monitoring-argocd.yaml${NC}"
}

function setup_argocd_notifications() {
  section "Setting up ArgoCD Notifications"
  
  local ARGOCD_NAMESPACE="argocd"
  
  # Create notifications configuration
  cat > cicd/argocd-notifications-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: $ARGOCD_NAMESPACE
data:
  service.slack: |
    token: \$slack-token
  template.app-deployed: |
    message: |
      {{if eq .serviceType "slack"}}:white_check_mark:{{end}} Application {{.app.metadata.name}} is now running new version.
  template.app-health-degraded: |
    message: |
      {{if eq .serviceType "slack"}}:exclamation:{{end}} Application {{.app.metadata.name}} has degraded.
  template.app-sync-failed: |
    message: |
      {{if eq .serviceType "slack"}}:exclamation:{{end}} Application {{.app.metadata.name}} sync is failed.
  trigger.on-deployed: |
    - description: Application is synced and healthy
      send:
      - app-deployed
      when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
  trigger.on-health-degraded: |
    - description: Application has degraded
      send:
      - app-health-degraded
      when: app.status.health.status == 'Degraded'
  trigger.on-sync-failed: |
    - description: Application syncing has failed
      send:
      - app-sync-failed
      when: app.status.operationState.phase in ['Error', 'Failed']
  subscriptions: |
    - recipients:
      - slack:general
      triggers:
      - on-deployed
      - on-health-degraded
      - on-sync-failed
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: $ARGOCD_NAMESPACE
type: Opaque
stringData:
  slack-token: "your-slack-bot-token-here"
EOF

  echo -e "${GREEN}✅ ArgoCD notifications configuration created${NC}"
  echo -e "${YELLOW}File created: cicd/argocd-notifications-config.yaml${NC}"
  echo -e "\n${YELLOW}To enable notifications:${NC}"
  echo -e "  1. Update the slack-token in the secret"
  echo -e "  2. Apply: kubectl apply -f cicd/argocd-notifications-config.yaml"
}

function check_argocd_status() {
  section "Checking ArgoCD Status"
  
  local ARGOCD_NAMESPACE="argocd"
  
  echo -e "${YELLOW}ArgoCD namespace pods:${NC}"
  kubectl get pods -n $ARGOCD_NAMESPACE 2>/dev/null || echo "ArgoCD not installed"
  
  echo -e "\n${YELLOW}ArgoCD services:${NC}"
  kubectl get svc -n $ARGOCD_NAMESPACE 2>/dev/null || echo "ArgoCD not installed"
  
  echo -e "\n${YELLOW}ArgoCD applications:${NC}"
  kubectl get applications -n $ARGOCD_NAMESPACE 2>/dev/null || echo "No applications found"
  
  echo -e "\n${YELLOW}ArgoCD projects:${NC}"
  kubectl get appprojects -n $ARGOCD_NAMESPACE 2>/dev/null || echo "No projects found"
  
  echo -e "\n${YELLOW}ArgoCD ingress:${NC}"
  kubectl get ingress -n $ARGOCD_NAMESPACE 2>/dev/null || echo "No ingress found"
  
  if kubectl get deployment argocd-server -n $ARGOCD_NAMESPACE &>/dev/null; then
    show_argocd_info
  fi
}

function uninstall_argocd() {
  section "Uninstalling ArgoCD"
  
  local ARGOCD_NAMESPACE="argocd"
  
  if ask_approval "Are you sure you want to uninstall ArgoCD? This will remove all applications and configurations."; then
    echo -e "${YELLOW}Removing ArgoCD...${NC}"
    kubectl delete namespace $ARGOCD_NAMESPACE --timeout=120s || true
    echo -e "${GREEN}ArgoCD uninstalled${NC}"
  else
    echo "ArgoCD uninstallation cancelled"
  fi
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running CI/CD script directly"
  PS3='Select CI/CD option: '
  options=(
    "Install ArgoCD"
    "Install ArgoCD CLI"
    "Setup ArgoCD Ingress"
    "Setup ArgoCD Projects"
    "Create Sample Application"
    "Create MongoDB Application"
    "Create Monitoring Application"
    "Setup Notifications"
    "Check ArgoCD Status"
    "Show ArgoCD Info"
    "Uninstall ArgoCD"
    "Complete CI/CD Setup"
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "Install ArgoCD")
        install_argocd
        ;;
      "Install ArgoCD CLI")
        install_argocd_cli
        ;;
      "Setup ArgoCD Ingress")
        setup_argocd_ingress
        ;;
      "Setup ArgoCD Projects")
        setup_argocd_projects
        ;;
      "Create Sample Application")
        create_sample_application
        ;;
      "Create MongoDB Application")
        create_mongodb_application
        ;;
      "Create Monitoring Application")
        create_monitoring_application
        ;;
      "Setup Notifications")
        setup_argocd_notifications
        ;;
      "Check ArgoCD Status")
        check_argocd_status
        ;;
      "Show ArgoCD Info")
        show_argocd_info
        ;;
      "Uninstall ArgoCD")
        uninstall_argocd
        ;;
      "Complete CI/CD Setup")
        install_argocd
        install_argocd_cli
        setup_argocd_projects
        create_mongodb_application
        create_monitoring_application
        setup_argocd_notifications
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