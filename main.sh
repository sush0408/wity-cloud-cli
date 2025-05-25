#!/bin/bash

set -e

# Source the common functions
if [[ -f "./common.sh" ]]; then
  source "./common.sh"
else
  echo "common.sh not found. This script requires common functions."
  exit 1
fi

# Source component scripts
component_scripts=(
  "./core.sh"
  "./storage.sh"
  "./monitoring.sh"
  "./management.sh"
  "./databases.sh"
  "./aws.sh"
  "./utilities.sh"
  "./cluster.sh"
)

for script in "${component_scripts[@]}"; do
  if [[ -f "$script" ]]; then
    source "$script"
  else
    echo "Warning: $script not found. Some functionality may be limited."
  fi
done

# Initialize variables
NODE_IP=$(get_node_ip)

# Check if script is being run as root
check_root

# Main menu function
function show_main_menu() {
  clear
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${GREEN}               Wity Cloud Deploy Tool                    ${NC}"
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${YELLOW}Node IP: ${NODE_IP}${NC}"
  
  # Check if RKE2 is running
  if systemctl is-active --quiet rke2-server 2>/dev/null; then
    echo -e "${GREEN}RKE2 Server Status: Running${NC}"
  elif systemctl is-active --quiet rke2-agent 2>/dev/null; then
    echo -e "${GREEN}RKE2 Agent Status: Running${NC}"
  else
    echo -e "${YELLOW}RKE2 Status: Not running${NC}"
  fi
  
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${YELLOW}Select a category to proceed:${NC}"
  echo ""
}

# Main menu options
PS3='Enter your choice (1-9): '
options=(
  "Core Components (RKE2, Helm, Cilium, MetalLB)"
  "Storage (Longhorn)"
  "Monitoring (Prometheus, Grafana, Loki)"
  "Management (Rancher, Cert Manager, Traefik, pgAdmin)"
  "Databases (MongoDB, PostgreSQL, MySQL, Redis, MariaDB)"
  "AWS Integration (S3, ECR, Route53)"
  "Cluster Management (Join, Info, Backup)"
  "Utilities (Status, TLS, Debugging)"
  "Quit"
)

# Function to show component menu
function show_component_menu() {
  local title=$1
  local script=$2
  
  # Extract all function names from the script
  # This only works for functions defined with the "function" keyword
  local functions=$(grep -oP "^function \K[a-zA-Z0-9_]+" "$script" | sort)
  local options=()
  
  # Build options array from function names
  while IFS= read -r func; do
    # Skip functions starting with "_" (considered private)
    if [[ "$func" != _* ]]; then
      options+=("$func")
    fi
  done <<< "$functions"
  
  options+=("Back to Main Menu")
  
  # Show component menu
  clear
  echo -e "${GREEN}=========================================================${NC}"
  echo -e "${GREEN}               $title                                    ${NC}"
  echo -e "${GREEN}=========================================================${NC}"
  
  select opt in "${options[@]}"; do
    if [[ "$opt" == "Back to Main Menu" ]]; then
      break
    elif [[ -n "$opt" ]]; then
      # Call the selected function
      $opt
    else
      echo "Invalid option"
    fi
  done
}

# Main loop
while true; do
  show_main_menu
  select opt in "${options[@]}"; do
    case $opt in
      "Core Components (RKE2, Helm, Cilium, MetalLB)")
        show_component_menu "Core Components" "./core.sh"
        break
        ;;
      "Storage (Longhorn)")
        show_component_menu "Storage" "./storage.sh"
        break
        ;;
      "Monitoring (Prometheus, Grafana, Loki)")
        show_component_menu "Monitoring" "./monitoring.sh"
        break
        ;;
      "Management (Rancher, Cert Manager, Traefik, pgAdmin)")
        show_component_menu "Management" "./management.sh"
        break
        ;;
      "Databases (MongoDB, PostgreSQL, MySQL, Redis, MariaDB)")
        show_component_menu "Databases" "./databases.sh"
        break
        ;;
      "AWS Integration (S3, ECR, Route53)")
        show_component_menu "AWS Integration" "./aws.sh"
        break
        ;;
      "Cluster Management (Join, Info, Backup)")
        show_component_menu "Cluster Management" "./cluster.sh"
        break
        ;;
      "Utilities (Status, TLS, Debugging)")
        show_component_menu "Utilities" "./utilities.sh"
        break
        ;;
      "Quit")
        echo "Goodbye!"
        exit 0
        ;;
      *)
        echo "Invalid option"
        ;;
    esac
  done
done
