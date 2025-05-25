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

function install_mongodb_percona() {
  section "Installing Percona MongoDB with Operator in 'pgo' namespace"
  
  # Check prerequisites
  if ! check_kubectl; then
    echo -e "${RED}Cannot access Kubernetes cluster${NC}"
    return 1
  fi

  local MONGODB_NAMESPACE="pgo"
  
  # Create MongoDB namespace
  if ask_approval "Do you want to create/configure the MongoDB namespace?"; then
    echo -e "${YELLOW}Creating MongoDB namespace...${NC}"
    
    # Create namespace if it doesn't exist
    if namespace_exists "$MONGODB_NAMESPACE"; then
      if ask_approval "Namespace '$MONGODB_NAMESPACE' already exists. Do you want to delete and recreate it?"; then
        echo "Deleting namespace $MONGODB_NAMESPACE..."
        kubectl delete namespace $MONGODB_NAMESPACE --timeout=120s || true
        sleep 10
        kubectl create namespace $MONGODB_NAMESPACE
      fi
    else
      kubectl create namespace $MONGODB_NAMESPACE
    fi
    
    kubectl config set-context $(kubectl config current-context) --namespace=$MONGODB_NAMESPACE
    echo "Namespace set to $MONGODB_NAMESPACE"
  fi

  # Install Percona MongoDB Operator
  if ask_approval "Do you want to install Percona MongoDB Operator?"; then
    echo -e "${YELLOW}Installing Percona MongoDB Operator...${NC}"
    
    # Check for operator directory
    if [ ! -d "percona-server-mongodb-operator" ]; then
      echo -e "${YELLOW}Cloning Percona MongoDB Operator repository...${NC}"
      git clone -b v1.14.0 https://github.com/percona/percona-server-mongodb-operator
      if [ ! -d "percona-server-mongodb-operator" ]; then
        echo -e "${RED}Failed to clone repository. Exiting.${NC}"
        return 1
      fi
    fi

    # Apply CRDs
    echo "Applying Percona MongoDB CRDs..."
    kubectl apply --server-side -f percona-server-mongodb-operator/deploy/crd.yaml || {
      echo -e "${RED}Failed to apply CRDs. Exiting.${NC}"
      return 1
    }
    
    # Check if operator is already installed
    if kubectl get deployment percona-server-mongodb-operator -n $MONGODB_NAMESPACE &>/dev/null; then
      if ask_approval "Percona MongoDB Operator is already installed. Do you want to reinstall it?"; then
        echo "Removing existing Percona MongoDB Operator..."
        kubectl delete deployment percona-server-mongodb-operator -n $MONGODB_NAMESPACE || true
        sleep 10
      fi
    fi

    # Apply RBAC and operator
    echo "Applying RBAC and deploying the operator..."
    kubectl apply -f percona-server-mongodb-operator/deploy/rbac.yaml
    kubectl apply -f percona-server-mongodb-operator/deploy/operator.yaml

    # Wait for operator to be ready
    echo "Waiting for MongoDB operator to be ready..."
    if ! wait_for_deployment "percona-server-mongodb-operator" "$MONGODB_NAMESPACE" 120; then
      echo -e "${RED}MongoDB operator failed to become ready${NC}"
      if ask_approval "Do you want to debug the operator pod?"; then
        OPERATOR_POD=$(kubectl get pods -n $MONGODB_NAMESPACE -l name=percona-server-mongodb-operator -o name | cut -d/ -f2)
        debug_pod $MONGODB_NAMESPACE $OPERATOR_POD
      fi
      echo "Continuing anyway..."
    fi
     
    # Additional wait to ensure CRDs are registered properly
    echo "Ensuring MongoDB CRDs are properly registered..."
    sleep 10
     
    # Verify CRDs are available
    if ! kubectl get crd perconaservermongodbs.psmdb.percona.com &>/dev/null; then
      echo -e "${RED}MongoDB CRDs not properly registered. This might cause issues later.${NC}"
    else
      echo "MongoDB CRDs successfully registered."
    fi
  fi

  # Create MongoDB secrets
  if ask_approval "Do you want to create MongoDB secrets?"; then
    echo -e "${YELLOW}Creating MongoDB secrets...${NC}"
    
    # Create directories if they don't exist
    mkdir -p databases/mongodb/deployments
    
    # Check if secrets already exist
    if check_secret "$MONGODB_NAMESPACE" "psmdb-secrets"; then
      if ask_approval "MongoDB secrets already exist. Do you want to replace them?"; then
        echo "Deleting existing MongoDB secrets..."
        kubectl delete secret psmdb-secrets -n $MONGODB_NAMESPACE || true
        sleep 5
      else
        echo "Using existing secrets."
      fi
    else
      # Create MongoDB users secrets
      cat > databases/mongodb/deployments/mongo-secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: psmdb-secrets
  namespace: $MONGODB_NAMESPACE
type: Opaque
data:
  MONGODB_BACKUP_USER: YmFja3Vw
  MONGODB_BACKUP_PASSWORD: YmFja3VwMTIzNDU2
  MONGODB_CLUSTER_ADMIN_USER: Y2x1c3RlckFkbWlu
  MONGODB_CLUSTER_ADMIN_PASSWORD: Y2x1c3RlckFkbWluMTIzNDU2
  MONGODB_CLUSTER_MONITOR_USER: Y2x1c3Rlck1vbml0b3I=
  MONGODB_CLUSTER_MONITOR_PASSWORD: Y2x1c3Rlck1vbml0b3IxMjM0NTY=
  MONGODB_USER_ADMIN_USER: dXNlckFkbWlu
  MONGODB_USER_ADMIN_PASSWORD: dXNlckFkbWluMTIzNDU2
  MONGODB_DATABASE_ADMIN_USER: ZGF0YWJhc2VBZG1pbg==
  MONGODB_DATABASE_ADMIN_PASSWORD: ZGF0YWJhc2VBZG1pbjEyMzQ1Ng==
  MONGODB_USER: dXNlcg==
  MONGODB_PASSWORD: dXNlcjEyMzQ1Ng==
EOF

      kubectl apply -f databases/mongodb/deployments/mongo-secrets.yaml || {
        echo -e "${RED}Failed to create MongoDB secrets. Exiting.${NC}"
        return 1
      }
      echo "MongoDB secrets created successfully."
    fi

    # S3 credentials for backups (optional)
    if ask_approval "Do you want to set up S3 backup credentials?"; then
      echo "Enter AWS Access Key ID:"
      read -r AWS_ACCESS_KEY_ID
      echo "Enter AWS Secret Access Key:"
      read -r AWS_SECRET_ACCESS_KEY
      
      # Convert to base64
      AWS_ACCESS_KEY_ID_B64=$(echo -n "$AWS_ACCESS_KEY_ID" | base64)
      AWS_SECRET_ACCESS_KEY_B64=$(echo -n "$AWS_SECRET_ACCESS_KEY" | base64)
      
      # Check if S3 secret already exists
      if check_secret "$MONGODB_NAMESPACE" "psmdb-s3-secret"; then
        if ask_approval "S3 credentials already exist. Do you want to replace them?"; then
          kubectl delete secret psmdb-s3-secret -n $MONGODB_NAMESPACE || true
          sleep 5
        fi
      fi
      
      cat > databases/mongodb/deployments/s3-credentials.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: psmdb-s3-secret
  namespace: $MONGODB_NAMESPACE
type: Opaque
data:
  AWS_ACCESS_KEY_ID: "${AWS_ACCESS_KEY_ID_B64}"
  AWS_SECRET_ACCESS_KEY: "${AWS_SECRET_ACCESS_KEY_B64}"
EOF
      
      kubectl apply -f databases/mongodb/deployments/s3-credentials.yaml || {
        echo -e "${RED}Failed to create S3 credentials. Continuing anyway...${NC}"
      }
      echo "S3 credentials applied."
    else
      echo "Skipping S3 credentials setup."
    fi
  fi

  # Deploy MongoDB cluster
  if ask_approval "Do you want to deploy MongoDB cluster with sharding and backup?"; then
    echo -e "${YELLOW}Deploying MongoDB cluster...${NC}"
    
    # Create directories if they don't exist
    mkdir -p databases/mongodb/deployments
    
    # Create the backup PVC if it doesn't exist
    if ! kubectl get pvc backup-pvc -n $MONGODB_NAMESPACE &>/dev/null; then
      echo "Creating backup PVC..."
      cat > databases/mongodb/deployments/backup-pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: $MONGODB_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-path
EOF
      kubectl apply -f databases/mongodb/deployments/backup-pvc.yaml || {
        echo -e "${RED}Failed to create backup PVC. Exiting.${NC}"
        return 1
      }
    fi

    # Create MongoDB cluster configuration
    cat > databases/mongodb/deployments/mongodb-config.yaml << EOF
apiVersion: psmdb.percona.com/v1
kind: PerconaServerMongoDB
metadata:
  name: psmdb
  namespace: $MONGODB_NAMESPACE
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
      size: 3
      affinity:
        antiAffinityTopologyKey: "none"
      podDisruptionBudget:
        maxUnavailable: 1
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: local-path
          resources:
            requests:
              storage: 3Gi
      sidecarVolumes:
        - name: backup-volume
          persistentVolumeClaim:
            claimName: backup-pvc
      resources:
        requests:
          cpu: 500m
          memory: 1G
        limits:
          cpu: 1000m
          memory: 2G
    - name: rs1
      size: 3
      affinity:
        antiAffinityTopologyKey: "none"
      podDisruptionBudget:
        maxUnavailable: 1
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: local-path
          resources:
            requests:
              storage: 3Gi
      sidecarVolumes:
        - name: backup-volume
          persistentVolumeClaim:
            claimName: backup-pvc
      resources:
        requests:
          cpu: 500m
          memory: 1G
        limits:
          cpu: 1000m
          memory: 2G

  sharding:
    enabled: true
    configsvrReplSet:
      size: 3
      affinity:
        antiAffinityTopologyKey: "none"
      podDisruptionBudget:
        maxUnavailable: 1
      volumeSpec:
        persistentVolumeClaim:
          storageClassName: local-path
          resources:
            requests:
              storage: 1Gi
      sidecarVolumes:
        - name: backup-volume
          persistentVolumeClaim:
            claimName: backup-pvc
      resources:
        requests:
          cpu: 250m
          memory: 512M
        limits:
          cpu: 500m
          memory: 1G

    mongos:
      size: 2
      affinity:
        antiAffinityTopologyKey: "none"
      resources:
        requests:
          cpu: 500m
          memory: 512M
        limits:
          cpu: 1000m
          memory: 1G

  backup:
    enabled: true
    image: percona/percona-backup-mongodb:2.0.3
    serviceAccountName: percona-server-mongodb-operator
    volumeMounts:
      - name: backup-volume
        mountPath: /backups
    storages:
      local-backup:
        type: filesystem
        filesystem:
          path: /backups
    tasks:
      - name: daily-backup
        enabled: true
        schedule: "0 0 * * *"
        storageName: local-backup
        compressionType: gzip
        compressionLevel: 3
EOF

    # Check if MongoDB is already deployed
    if kubectl get psmdb -n $MONGODB_NAMESPACE psmdb &>/dev/null; then
      if ask_approval "MongoDB cluster is already deployed. Do you want to delete and redeploy it?"; then
        echo "Deleting existing MongoDB cluster..."
        kubectl delete psmdb -n $MONGODB_NAMESPACE psmdb || true
        sleep 30  # Give it time to clean up
      fi
    fi

    # Deploy MongoDB cluster
    echo "Deploying MongoDB cluster..."
    kubectl apply -f databases/mongodb/deployments/mongodb-config.yaml || {
      echo -e "${RED}Failed to deploy MongoDB cluster${NC}"
      return 1
    }
     
    echo "Waiting for MongoDB cluster to become ready (this may take several minutes)..."
    TIMEOUT=900  # 15 minutes timeout
    INTERVAL=15   # Check every 15 seconds
    ELAPSED=0
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
      STATUS=$(kubectl get psmdb -n $MONGODB_NAMESPACE psmdb -o jsonpath='{.status.state}' 2>/dev/null)
      ENDPOINT=$(kubectl get psmdb -n $MONGODB_NAMESPACE psmdb -o jsonpath='{.status.host}' 2>/dev/null)
      
      if [ "$STATUS" = "ready" ] && [ -n "$ENDPOINT" ]; then
        echo -e "${GREEN}MongoDB cluster is ready!${NC}"
        echo "Cluster endpoint: $ENDPOINT"
        kubectl get psmdb -n $MONGODB_NAMESPACE
        break
      else
        echo "Waiting for MongoDB cluster to become ready... Current status: $STATUS"
        
        # Display more detailed diagnostics
        if [ "$STATUS" = "error" ]; then
          echo -e "${YELLOW}Cluster in error state. Checking detailed status:${NC}"
          kubectl get psmdb psmdb -n $MONGODB_NAMESPACE -o jsonpath='{.status.message}'
          echo ""
        fi
        
        # Show pod status for better debugging
        echo "Current pod status:"
        kubectl get pods -n $MONGODB_NAMESPACE -l app.kubernetes.io/name=percona-server-mongodb
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
      fi
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo -e "${RED}Timeout waiting for MongoDB cluster to become ready.${NC}"
      echo "Current cluster status:"
      kubectl get psmdb -n $MONGODB_NAMESPACE
      echo "Current pod status:"
      kubectl get pods -n $MONGODB_NAMESPACE -l app.kubernetes.io/name=percona-server-mongodb
      
      if ask_approval "Would you like to continue despite the timeout?"; then
        echo "Continuing with deployment..."
      else
        echo "Exiting deployment due to timeout."
        return 1
      fi
    fi
    
    echo "Verifying MongoDB connectivity..."
    kubectl run -i --rm --tty percona-client-test --image=percona/percona-server-mongodb:5.0.14-12 --restart=Never --namespace=$MONGODB_NAMESPACE -- bash -c "echo 'Attempting to connect to MongoDB...' && mongosh --eval 'db.version()' 'mongodb://databaseAdmin:databaseAdmin123456@psmdb-mongos.$MONGODB_NAMESPACE.svc.cluster.local/admin?ssl=false'" || {
      echo -e "${YELLOW}Could not verify MongoDB connectivity.${NC}"
      echo "You can manually verify connectivity after deployment completes."
    }
  fi

  # Display connection information
  echo -e "${GREEN}Percona MongoDB deployment completed!${NC}"
  echo "=================================================="
  echo "MongoDB connection details:"
  echo "  - Connection string: mongodb://databaseAdmin:databaseAdmin123456@psmdb-mongos.$MONGODB_NAMESPACE.svc.cluster.local/admin"
  echo "  - Namespace: $MONGODB_NAMESPACE"
  echo ""
  echo "MongoDB cluster configuration:"
  echo "  - Sharded architecture with 2 shards (rs0: 3 replicas, rs1: 3 replicas)"
  echo "  - 3 config servers for increased reliability"
  echo "  - 2 mongos query routers with anti-affinity configuration"
  echo "  - Automated daily backups enabled"
  echo ""
  echo "To check cluster status:"
  echo "  kubectl get psmdb -n $MONGODB_NAMESPACE"
  echo "  kubectl get pods -n $MONGODB_NAMESPACE"
  echo ""
  echo "To debug MongoDB pods:"
  echo "  kubectl describe pods <pod-name> -n $MONGODB_NAMESPACE"
  echo "  kubectl logs <pod-name> -n $MONGODB_NAMESPACE"
  echo "=================================================="
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
  
  # Use safe installation
  safe_helm_install "my-redis" "bitnami/redis" "database" \
    --set auth.enabled=false
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Redis installed in the 'database' namespace${NC}"
    echo -e "${YELLOW}Authentication disabled for demonstration purposes${NC}"
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

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Database script directly"
  PS3='Select database to install: '
  options=("MongoDB (Percona Operator)" "PostgreSQL" "MySQL" "Redis" "MariaDB" "All Databases" "Quit")
  
  select opt in "${options[@]}"; do
    case $opt in
      "MongoDB (Percona Operator)")
        install_mongodb_percona
        ;;
      "PostgreSQL")
        install_postgres_bitnami
        ;;
      "MySQL")
        install_mysql_bitnami
        ;;
      "Redis")
        install_redis_bitnami
        ;;
      "MariaDB")
        install_mariadb_bitnami
        ;;
      "All Databases")
        install_mongodb_percona
        install_postgres_bitnami
        install_mysql_bitnami
        install_redis_bitnami
        install_mariadb_bitnami
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