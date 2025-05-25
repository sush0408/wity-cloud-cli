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
  kubectl create namespace monitoring || true
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --version 56.7.0
  
  echo -e "${GREEN}Prometheus and Grafana monitoring stack installed${NC}"
  echo -e "${YELLOW}Access the dashboards through Rancher or by setting up ingress rules${NC}"
}

function install_loki() {
  section "Installing Loki + Promtail"
  kubectl create namespace loki || true
  helm install loki grafana/loki-stack --namespace loki --version 5.42.0 --set promtail.enabled=true
  
  echo -e "${GREEN}Loki log aggregation system installed${NC}"
  echo -e "${YELLOW}Configure Grafana to use Loki as a data source to view logs${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Monitoring script directly"
  PS3='Select monitoring component: '
  options=("Prometheus + Grafana" "Loki + Promtail" "All Monitoring Components" "Quit")
  
  select opt in "${options[@]}"; do
    case $opt in
      "Prometheus + Grafana")
        install_monitoring
        ;;
      "Loki + Promtail")
        install_loki
        ;;
      "All Monitoring Components")
        install_monitoring
        install_loki
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