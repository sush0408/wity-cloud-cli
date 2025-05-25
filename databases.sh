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

function install_mongodb_percona() {
  section "Installing Percona MongoDB in 'database' namespace"
  kubectl create namespace database || true
  helm repo add percona https://percona.github.io/percona-helm-charts/ || true
  helm repo update
  helm install my-mongo percona/psmdb --namespace database --set pmm.enabled=false
  
  echo -e "${GREEN}Percona MongoDB installed in the 'database' namespace${NC}"
}

function install_postgres_bitnami() {
  section "Installing PostgreSQL (Bitnami)"
  kubectl create namespace database || true
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  helm install my-postgres bitnami/postgresql --namespace database --set auth.postgresPassword=secretpassword
  
  echo -e "${GREEN}PostgreSQL installed in the 'database' namespace${NC}"
  echo -e "${YELLOW}Default password: secretpassword${NC}"
}

function install_mysql_bitnami() {
  section "Installing MySQL (Bitnami)"
  kubectl create namespace database || true
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  helm install my-mysql bitnami/mysql --namespace database --set auth.rootPassword=secretpassword
  
  echo -e "${GREEN}MySQL installed in the 'database' namespace${NC}"
  echo -e "${YELLOW}Root password: secretpassword${NC}"
}

function install_redis_bitnami() {
  section "Installing Redis (Bitnami)"
  kubectl create namespace database || true
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  helm install my-redis bitnami/redis --namespace database --set auth.enabled=false
  
  echo -e "${GREEN}Redis installed in the 'database' namespace${NC}"
  echo -e "${YELLOW}Authentication disabled for demonstration purposes${NC}"
}

function install_mariadb_bitnami() {
  section "Installing MariaDB (Bitnami)"
  kubectl create namespace database || true
  helm repo add bitnami https://charts.bitnami.com/bitnami || true
  helm repo update
  helm install my-mariadb bitnami/mariadb --namespace database --set auth.rootPassword=secretpassword
  
  echo -e "${GREEN}MariaDB installed in the 'database' namespace${NC}"
  echo -e "${YELLOW}Root password: secretpassword${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Database script directly"
  PS3='Select database to install: '
  options=("MongoDB (Percona)" "PostgreSQL" "MySQL" "Redis" "MariaDB" "All Databases" "Quit")
  
  select opt in "${options[@]}"; do
    case $opt in
      "MongoDB (Percona)")
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