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

# Function to check if a secret exists
check_secret() {
  local namespace=$1
  local secret=$2
  kubectl get secret -n $namespace $secret &>/dev/null
  return $?
}

# Function to debug a Pod
debug_pod() {
  local namespace=$1
  local pod=$2
  
  echo -e "${YELLOW}=== Debugging Pod $pod in namespace $namespace ===${NC}"
  echo -e "${YELLOW}Pod status:${NC}"
  kubectl describe pod -n $namespace $pod
  
  echo -e "${YELLOW}Pod logs:${NC}"
  kubectl logs -n $namespace $pod --all-containers
}

function create_mongodb_secrets_database_ns() {
  local namespace=$1
  
  # Create directories if they don't exist
  mkdir -p databases/mongodb/database-namespace
  
  # Check if secrets already exist
  if kubectl get secret psmdb-secrets -n $namespace &>/dev/null; then
    echo -e "${GREEN}MongoDB secrets already exist${NC}"
    return 0
  fi
  
  echo "Creating MongoDB user secrets..."
  cat > databases/mongodb/database-namespace/secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: psmdb-secrets
  namespace: $namespace
type: Opaque
stringData:
  MONGODB_BACKUP_USER: backup
  MONGODB_BACKUP_PASSWORD: backup123456
  MONGODB_CLUSTER_ADMIN_USER: clusterAdmin
  MONGODB_CLUSTER_ADMIN_PASSWORD: clusterAdmin123456
  MONGODB_CLUSTER_MONITOR_USER: clusterMonitor
  MONGODB_CLUSTER_MONITOR_PASSWORD: clusterMonitor123456
  MONGODB_USER_ADMIN_USER: userAdmin
  MONGODB_USER_ADMIN_PASSWORD: userAdmin123456
  PMM_SERVER_USER: admin
  PMM_SERVER_PASSWORD: admin
EOF

  # Apply the secrets
  kubectl apply -f databases/mongodb/database-namespace/secrets.yaml -n $namespace
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ MongoDB secrets created successfully${NC}"
  else
    echo -e "${RED}❌ Failed to create MongoDB secrets${NC}"
    return 1
  fi
}

function create_mongodb_cluster_database_ns() {
  local namespace=$1
  
  # Create directories if they don't exist
  mkdir -p databases/mongodb/database-namespace
  
  # Create backup PVC first
  cat > databases/mongodb/database-namespace/backup-pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: $namespace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: longhorn
EOF

  # Apply backup PVC
  kubectl apply -f databases/mongodb/database-namespace/backup-pvc.yaml
  
  # Create optimized cluster configuration for single-node deployment
  cat > databases/mongodb/database-namespace/mongodb-cluster.yaml << EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: psmdb
  namespace: $namespace
spec:
  crVersion: 1.14.0
  image: percona/percona-server-mongodb:5.0.14-12
  allowUnsafeConfigurations: true
  upgradeOptions:
    apply: disabled
    schedule: "0 2 * * *"
  secrets:
    users: psmdb-secrets
  replsets:
    - name: rs0
      size: 1
      affinity:
        antiAffinityTopologyKey: "none"
      podDisruptionBudget:
        maxUnavailable: 1
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: longhorn
          resources:
            requests:
              storage: 3Gi
      resources:
        requests:
          cpu: 1000m
          memory: 2G
        limits:
          cpu: 2000m
          memory: 4G
    - name: rs1
      size: 1
      affinity:
        antiAffinityTopologyKey: "none"
      podDisruptionBudget:
        maxUnavailable: 1
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: longhorn
          resources:
            requests:
              storage: 3Gi
      resources:
        requests:
          cpu: 1000m
          memory: 2G
        limits:
          cpu: 2000m
          memory: 4G

  sharding:
    enabled: true
    configsvrReplSet:
      size: 2
      affinity:
        antiAffinityTopologyKey: "none"
      podDisruptionBudget:
        maxUnavailable: 1
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: longhorn
          resources:
            requests:
              storage: 1Gi
      resources:
        requests:
          cpu: 500m
          memory: 1G
        limits:
          cpu: 1000m
          memory: 2G

    mongos:
      size: 1
      affinity:
        antiAffinityTopologyKey: "none"
      resources:
        requests:
          cpu: 1000m
          memory: 1G
        limits:
          cpu: 2000m
          memory: 2G
EOF

  echo -e "${GREEN}✅ MongoDB optimized sharded cluster configuration created${NC}"
}

function show_mongodb_connection_info_database_ns() {
  local namespace=$1
  
  echo -e "\n${YELLOW}MongoDB Sharded Cluster Connection Information:${NC}"
  
  # Get cluster endpoint
  local endpoint=$(kubectl get psmdb psmdb -n $namespace -o jsonpath='{.status.host}' 2>/dev/null)
  if [[ -n "$endpoint" ]]; then
    echo "Cluster Endpoint: $endpoint"
  fi
  
  # Get service information
  echo -e "\n${YELLOW}Services:${NC}"
  kubectl get svc -n $namespace | grep psmdb
  
  # Show how to get credentials
  echo -e "\n${YELLOW}To get MongoDB credentials:${NC}"
  echo "kubectl get secret psmdb-secrets -n $namespace -o yaml"
  
  # Show connection examples for sharded cluster
  echo -e "\n${YELLOW}Connection Examples (Sharded Cluster):${NC}"
  echo "# Connect to MongoDB via mongos router from within cluster:"
  echo "kubectl run -it --rm --image=mongo:5.0 --restart=Never mongo-client -- mongo mongodb://clusterAdmin:clusterAdmin123456@psmdb-mongos.$namespace.svc.cluster.local/admin"
  
  echo -e "\n# Connect to specific replica set (rs0):"
  echo "kubectl run -it --rm --image=mongo:5.0 --restart=Never mongo-client -- mongo mongodb://clusterAdmin:clusterAdmin123456@psmdb-rs0.$namespace.svc.cluster.local/admin"
  
  echo -e "\n# Connect to specific replica set (rs1):"
  echo "kubectl run -it --rm --image=mongo:5.0 --restart=Never mongo-client -- mongo mongodb://clusterAdmin:clusterAdmin123456@psmdb-rs1.$namespace.svc.cluster.local/admin"
  
  echo -e "\n# Port forward for external access (mongos router):"
  echo "kubectl port-forward svc/psmdb-mongos -n $namespace 27017:27017"
  
  echo -e "\n${YELLOW}Backup Information:${NC}"
  echo "# Check backup status:"
  echo "kubectl get psmdb-backup -n $namespace"
  echo ""
  echo "# Manual backup:"
  echo "kubectl apply -f - <<EOF"
  echo "apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: manual-backup-\$(date +%Y%m%d-%H%M%S)
  namespace: $namespace
spec:
  clusterName: psmdb
  storageName: local-backup
EOF"
  
  echo -e "\n${YELLOW}Useful Commands:${NC}"
  echo "# Check cluster status:"
  echo "kubectl get psmdb psmdb -n $namespace"
  echo ""
  echo "# Check all pods (should show rs0, rs1, cfg, mongos):"
  echo "kubectl get pods -n $namespace"
  echo ""
  echo "# Check sharding status:"
  echo "kubectl exec -it psmdb-mongos-0 -n $namespace -- mongo admin --eval 'sh.status()'"
  echo ""
  echo "# Check replica set status:"
  echo "kubectl exec -it psmdb-rs0-0 -n $namespace -- mongo admin --eval 'rs.status()'"
}

function create_mongodb_backup_config() {
  local namespace=$1
  
  echo -e "${YELLOW}Creating MongoDB backup configuration...${NC}"
  
  # Create a separate backup configuration file
  cat > databases/mongodb/database-namespace/mongodb-backup.yaml << EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDBBackup
metadata:
  name: manual-backup-$(date +%Y%m%d-%H%M%S)
  namespace: $namespace
spec:
  clusterName: psmdb
  storageName: local-backup
EOF

  echo -e "${GREEN}✅ MongoDB backup configuration created${NC}"
  echo -e "${YELLOW}To create a manual backup, run:${NC}"
  echo "kubectl apply -f databases/mongodb/database-namespace/mongodb-backup.yaml"
}

function wait_for_mongodb_cluster() {
  local namespace=$1
  local timeout=${2:-900}  # Default 15 minutes
  
  echo -e "${YELLOW}Waiting for MongoDB sharded cluster to be ready...${NC}"
  echo "This may take up to $((timeout/60)) minutes for a sharded cluster..."
  
  local elapsed=0
  local interval=15  # Check every 15 seconds
  
  while [[ $elapsed -lt $timeout ]]; do
    local status=$(kubectl get psmdb psmdb -n $namespace -o jsonpath='{.status.state}' 2>/dev/null || echo "")
    local endpoint=$(kubectl get psmdb psmdb -n $namespace -o jsonpath='{.status.host}' 2>/dev/null || echo "")
    
    if [[ "$status" == "ready" && -n "$endpoint" ]]; then
      echo -e "${GREEN}✅ MongoDB sharded cluster is ready!${NC}"
      echo "Cluster endpoint: $endpoint"
      return 0
    else
      echo "Waiting for MongoDB cluster... Current status: ${status:-initializing}"
      
      # Show pod count for better monitoring
      local pod_count=$(kubectl get pods -n $namespace -l app.kubernetes.io/name=percona-server-mongodb --no-headers 2>/dev/null | wc -l)
      local ready_count=$(kubectl get pods -n $namespace -l app.kubernetes.io/name=percona-server-mongodb --no-headers 2>/dev/null | grep "1/1" | wc -l)
      echo "MongoDB pods: $ready_count/$pod_count ready"
      
      # Check for any failed pods
      local failed_pods=$(kubectl get pods -n $namespace -l app.kubernetes.io/name=percona-server-mongodb -o jsonpath='{range .items[?(@.status.phase=="Failed")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
      if [[ -n "$failed_pods" ]]; then
        echo -e "${RED}Failed pods detected: $failed_pods${NC}"
      fi
      
      sleep $interval
      elapsed=$((elapsed + interval))
    fi
  done
  
  echo -e "${RED}❌ Timeout waiting for MongoDB cluster to be ready${NC}"
  echo "Current status:"
  kubectl get psmdb psmdb -n $namespace 2>/dev/null || echo "Cluster not found"
  kubectl get pods -n $namespace -l app.kubernetes.io/name=percona-server-mongodb 2>/dev/null || echo "No pods found"
  return 1
}

function install_mongodb_percona() {
  section "Installing Percona MongoDB with Operator in 'database' namespace"
  
  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    return 1
  fi

  local MONGODB_NAMESPACE="database"
  
  # Create database namespace if it doesn't exist
  if ! namespace_exists "$MONGODB_NAMESPACE"; then
    echo -e "${YELLOW}Creating database namespace...${NC}"
    kubectl create namespace $MONGODB_NAMESPACE
    echo -e "${GREEN}Created namespace '$MONGODB_NAMESPACE'${NC}"
  else
    echo -e "${GREEN}Namespace '$MONGODB_NAMESPACE' already exists${NC}"
  fi
  
  # Set context to database namespace
  kubectl config set-context $(kubectl config current-context) --namespace=$MONGODB_NAMESPACE
  echo "Namespace context set to $MONGODB_NAMESPACE"

  # Step 1: Clone the operator repository (using working version 1.14.0)
  if [[ ! -d "percona-server-mongodb-operator" ]]; then
    echo -e "${YELLOW}Cloning Percona MongoDB Operator repository...${NC}"
    git clone -b v1.14.0 https://github.com/percona/percona-server-mongodb-operator
    if [[ ! -d "percona-server-mongodb-operator" ]]; then
      echo -e "${RED}Failed to clone repository${NC}"
      return 1
    fi
    
    # Replace all occurrences of 'my-cluster-name' with 'psmdb' in the operator files
    echo -e "${YELLOW}Updating operator files to use 'psmdb' naming convention...${NC}"
    find percona-server-mongodb-operator -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i 's/my-cluster-name/psmdb/g' {} \;
    echo -e "${GREEN}✅ Operator files updated with psmdb naming${NC}"
  else
    echo -e "${GREEN}Percona MongoDB Operator repository already exists${NC}"
    
    # Check if we need to update existing files
    if grep -r "my-cluster-name" percona-server-mongodb-operator/ >/dev/null 2>&1; then
      echo -e "${YELLOW}Updating existing operator files to use 'psmdb' naming convention...${NC}"
      find percona-server-mongodb-operator -type f \( -name "*.yaml" -o -name "*.yml" \) -exec sed -i 's/my-cluster-name/psmdb/g' {} \;
      echo -e "${GREEN}✅ Existing operator files updated with psmdb naming${NC}"
    else
      echo -e "${GREEN}Operator files already use psmdb naming${NC}"
    fi
  fi
  
  cd percona-server-mongodb-operator

  # Step 2: Apply CRD (cluster-wide, only once)
  echo -e "${YELLOW}Installing Custom Resource Definitions...${NC}"
  kubectl apply --server-side -f deploy/crd.yaml
  
  # Step 3: Apply RBAC in database namespace
  echo -e "${YELLOW}Setting up RBAC in database namespace...${NC}"
  kubectl apply -f deploy/rbac.yaml -n $MONGODB_NAMESPACE
  
  # Step 4: Install operator in database namespace
  echo -e "${YELLOW}Installing operator in database namespace...${NC}"
  kubectl apply -f deploy/operator.yaml -n $MONGODB_NAMESPACE
  
  cd ..
  
  # Wait for operator to be ready
  echo -e "${YELLOW}Waiting for operator to be ready...${NC}"
  kubectl wait --for=condition=available --timeout=300s deployment/percona-server-mongodb-operator -n $MONGODB_NAMESPACE
  
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}Operator failed to become ready${NC}"
    return 1
  fi

  # Step 5: Create MongoDB secrets
  echo -e "${YELLOW}Creating MongoDB secrets...${NC}"
  create_mongodb_secrets_database_ns "$MONGODB_NAMESPACE"

  # Step 6: Create MongoDB cluster configuration (with sharding and backup)
  echo -e "${YELLOW}Creating MongoDB cluster configuration with sharding and backup...${NC}"
  create_mongodb_cluster_database_ns "$MONGODB_NAMESPACE"

  # Step 7: Deploy MongoDB cluster
  echo -e "${YELLOW}Deploying MongoDB sharded cluster...${NC}"
  kubectl apply -f databases/mongodb/database-namespace/mongodb-cluster.yaml -n $MONGODB_NAMESPACE

  # Wait for cluster to be ready using improved monitoring
  if ! wait_for_mongodb_cluster "$MONGODB_NAMESPACE" 900; then
    echo -e "${RED}❌ MongoDB cluster deployment failed${NC}"
    echo "Check operator logs: kubectl logs -n $MONGODB_NAMESPACE deployment/percona-server-mongodb-operator"
    echo "Check cluster status: kubectl describe psmdb psmdb -n $MONGODB_NAMESPACE"
    return 1
  fi

  # Show cluster information
  echo -e "\n${GREEN}MongoDB sharded cluster deployed successfully!${NC}"
  echo -e "${YELLOW}Cluster Architecture:${NC}"
  echo "- 2 Shards: rs0 (1 replica), rs1 (1 replica)"
  echo "- 2 Config servers for metadata"
  echo "- 1 Mongos router for client connections"
  echo "- Optimized for single-node deployment"
  
  echo -e "\n${YELLOW}Cluster Information:${NC}"
  kubectl get psmdb psmdb -n $MONGODB_NAMESPACE
  
  echo -e "\n${YELLOW}MongoDB Pods:${NC}"
  kubectl get pods -n $MONGODB_NAMESPACE -l app.kubernetes.io/name=percona-server-mongodb
  
  echo -e "\n${YELLOW}MongoDB Services:${NC}"
  kubectl get svc -n $MONGODB_NAMESPACE | grep psmdb
  
  # Create backup configuration
  create_mongodb_backup_config "$MONGODB_NAMESPACE"
  
  # Show connection information
  show_mongodb_connection_info_database_ns "$MONGODB_NAMESPACE"
}

function install_postgres_bitnami() {
  section "Installing PostgreSQL (Bitnami)"
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  
  # Use safe installation
  safe_helm_install "my-postgres" "bitnami/postgresql" "database" \
    --set auth.postgresPassword=secretpassword
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}PostgreSQL installed in the 'database' namespace${NC}"
    echo -e "${YELLOW}Default password: secretpassword${NC}"
  fi
}

function install_mysql_bitnami() {
  section "Installing MySQL (Bitnami)"
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  
  # Use safe installation
  safe_helm_install "my-mysql" "bitnami/mysql" "database" \
    --set auth.rootPassword=secretpassword
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}MySQL installed in the 'database' namespace${NC}"
    echo -e "${YELLOW}Root password: secretpassword${NC}"
  fi
}

function install_redis_bitnami() {
  section "Installing Redis (Bitnami)"
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  
  # Use safe installation with redis name
  safe_helm_install "redis" "bitnami/redis" "database" \
    --set auth.password=secretpassword
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Redis installed in the 'database' namespace${NC}"
    echo -e "${YELLOW}Default password: secretpassword${NC}"
  fi
}

function install_mariadb_bitnami() {
  section "Installing MariaDB (Bitnami)"
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  
  # Use safe installation
  safe_helm_install "my-mariadb" "bitnami/mariadb" "database" \
    --set auth.rootPassword=secretpassword
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}MariaDB installed in the 'database' namespace${NC}"
    echo -e "${YELLOW}Root password: secretpassword${NC}"
  fi
}

function setup_mongodb_ingress() {
  section "Setting up MongoDB Ingress"
  
  local namespace="database"
  NODE_IP=$(hostname -I | awk '{print $1}')
  
  # Check if MongoDB cluster exists
  if ! kubectl get psmdb psmdb -n $namespace &>/dev/null; then
    echo -e "${RED}MongoDB cluster not found in $namespace namespace${NC}"
    return 1
  fi
  
  # Create ingress for MongoDB (for external access via MongoDB Compass or other tools)
  cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mongodb-ingress
  namespace: $namespace
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.rule: Host(\`
EOF
}

function troubleshoot_mongodb() {
  local namespace=${1:-"database"}
  
  section "MongoDB Troubleshooting for namespace: $namespace"
  
  echo -e "${YELLOW}=== MongoDB Cluster Status ===${NC}"
  if kubectl get psmdb psmdb -n $namespace &>/dev/null; then
    kubectl get psmdb psmdb -n $namespace
    echo ""
    kubectl describe psmdb psmdb -n $namespace | grep -A 10 "Status:"
  else
    echo -e "${RED}No MongoDB cluster found in $namespace namespace${NC}"
  fi
  
  echo -e "\n${YELLOW}=== MongoDB Operator Status ===${NC}"
  if kubectl get deployment percona-server-mongodb-operator -n $namespace &>/dev/null; then
    kubectl get deployment percona-server-mongodb-operator -n $namespace
    echo ""
    echo "Operator logs (last 20 lines):"
    kubectl logs -n $namespace deployment/percona-server-mongodb-operator --tail=20
  else
    echo -e "${RED}MongoDB operator not found in $namespace namespace${NC}"
  fi
  
  echo -e "\n${YELLOW}=== MongoDB Pods Status ===${NC}"
  kubectl get pods -n $namespace -l app.kubernetes.io/name=percona-server-mongodb 2>/dev/null || echo "No MongoDB pods found"
  
  echo -e "\n${YELLOW}=== MongoDB Services ===${NC}"
  kubectl get svc -n $namespace | grep psmdb || echo "No MongoDB services found"
  
  echo -e "\n${YELLOW}=== MongoDB Secrets ===${NC}"
  kubectl get secrets -n $namespace | grep psmdb || echo "No MongoDB secrets found"
  
  echo -e "\n${YELLOW}=== MongoDB PVCs ===${NC}"
  kubectl get pvc -n $namespace | grep -E "(psmdb|backup)" || echo "No MongoDB PVCs found"
  
  echo -e "\n${YELLOW}=== Recent Events ===${NC}"
  kubectl get events -n $namespace --sort-by='.lastTimestamp' | tail -10
  
  echo -e "\n${YELLOW}=== Troubleshooting Tips ===${NC}"
  echo "1. Check operator logs: kubectl logs -n $namespace deployment/percona-server-mongodb-operator"
  echo "2. Check cluster status: kubectl describe psmdb psmdb -n $namespace"
  echo "3. Check pod logs: kubectl logs -n $namespace <pod-name> -c mongod"
  echo "4. Check secrets: kubectl get secret psmdb-secrets -n $namespace -o yaml"
  echo "5. Restart operator: kubectl rollout restart deployment/percona-server-mongodb-operator -n $namespace"
}

function test_mongodb_connection() {
  local namespace=${1:-"database"}
  
  section "Testing MongoDB Connection"
  
  # Check if cluster is ready
  local status=$(kubectl get psmdb psmdb -n $namespace -o jsonpath='{.status.state}' 2>/dev/null)
  if [[ "$status" != "ready" ]]; then
    echo -e "${RED}MongoDB cluster is not ready. Current status: $status${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}Testing MongoDB connection via mongos router...${NC}"
  
  # Test connection using a temporary pod
  kubectl run -it --rm --image=mongo:5.0 --restart=Never mongo-test-$(date +%s) -n $namespace -- \
    mongo mongodb://clusterAdmin:clusterAdmin123456@psmdb-mongos.$namespace.svc.cluster.local/admin \
    --eval "
      print('=== MongoDB Connection Test ===');
      print('MongoDB Version: ' + version());
      print('Current Database: ' + db.getName());
      print('Server Status:');
      printjson(db.serverStatus().host);
      print('Sharding Status:');
      printjson(sh.status());
      print('=== Test Completed Successfully ===');
    " 2>/dev/null || {
    echo -e "${RED}Connection test failed${NC}"
    return 1
  }
  
  echo -e "${GREEN}✅ MongoDB connection test successful${NC}"
}

function install_pmm_server_for_mongodb() {
  local namespace=${1:-"monitoring"}
  
  section "Installing PMM Server for MongoDB Monitoring"
  
  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    return 1
  fi

  # Create monitoring namespace if it doesn't exist
  if ! namespace_exists "$namespace"; then
    echo -e "${YELLOW}Creating monitoring namespace...${NC}"
    kubectl create namespace $namespace
    echo -e "${GREEN}Created namespace '$namespace'${NC}"
  else
    echo -e "${GREEN}Namespace '$namespace' already exists${NC}"
  fi

  # Create PMM Server configuration directory
  mkdir -p monitoring/pmm

  # Check if PMM is already installed
  if kubectl get deployment pmm-server -n $namespace &>/dev/null; then
    if ask_approval "PMM Server is already installed. Do you want to reinstall it?"; then
      echo "Removing existing PMM Server..."
      kubectl delete deployment pmm-server -n $namespace || true
      kubectl delete service pmm-server -n $namespace || true
      kubectl delete pvc pmm-data -n $namespace || true
      kubectl delete secret pmm-secrets -n $namespace || true
      kubectl delete ingress pmm-ingress -n $namespace || true
      sleep 10
    else
      echo -e "${GREEN}Using existing PMM Server installation${NC}"
      return 0
    fi
  fi

  echo "Creating PMM Server configuration with longhorn storage..."
  cat > monitoring/pmm/pmm-server.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pmm-data
  namespace: $namespace
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
  namespace: $namespace
type: Opaque
data:
  PMM_ADMIN_PASSWORD: YWRtaW4tcGFzc3dvcmQ=  # admin-password
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pmm-server
  namespace: $namespace
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
  namespace: $namespace
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
  namespace: $namespace
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
  kubectl apply -f monitoring/pmm/pmm-server.yaml

  # Wait for PMM to be ready
  echo -e "${YELLOW}Waiting for PMM Server to be ready...${NC}"
  kubectl wait --namespace $namespace --for=condition=available deployment/pmm-server --timeout=300s || {
    echo -e "${RED}PMM Server failed to become ready${NC}"
    return 1
  }

  # Show PMM information
  echo -e "\n${GREEN}PMM Server deployed successfully!${NC}"
  echo -e "${YELLOW}PMM Server Information:${NC}"
  kubectl get deployment pmm-server -n $namespace
  kubectl get service pmm-server -n $namespace
  
  local pmm_ip=$(kubectl get service pmm-server -n $namespace -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [[ -n "$pmm_ip" ]]; then
    echo -e "${GREEN}PMM Server is available at: http://$pmm_ip${NC}"
    echo -e "${YELLOW}Username: admin${NC}"
    echo -e "${YELLOW}Password: admin-password${NC}"
    echo -e "\n${YELLOW}To access PMM externally, run:${NC}"
    echo "kubectl port-forward svc/pmm-server 8080:80 -n $namespace"
    echo "Then visit: http://localhost:8080"
  fi
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Database script directly"
  PS3='Select database option: '
  options=(
    "PostgreSQL" 
    "Percona MongoDB" 
    "Setup MongoDB Ingress"
    "Test MongoDB Connection"
    "Troubleshoot MongoDB"
    "Create MongoDB Backup"
    "Install PMM Server"
    "Check Database Status"
    "PgAdmin" 
    "All Databases" 
    "Quit"
  )
  
  select opt in "${options[@]}"; do
    case $opt in
      "PostgreSQL")
        install_postgres_bitnami
        ;;
      "Percona MongoDB")
        install_mongodb_percona
        ;;
      "Setup MongoDB Ingress")
        setup_mongodb_ingress
        ;;
      "Test MongoDB Connection")
        test_mongodb_connection
        ;;
      "Troubleshoot MongoDB")
        troubleshoot_mongodb
        ;;
      "Create MongoDB Backup")
        create_mongodb_backup_config "database"
        ;;
      "Install PMM Server")
        install_pmm_server_for_mongodb
        ;;
      "Check Database Status")
        check_database_status
        ;;
      "PgAdmin")
        install_pgadmin
        ;;
      "All Databases")
        install_postgres_bitnami
        install_mongodb_percona
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