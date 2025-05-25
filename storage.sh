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

function install_longhorn() {
  section "Installing Longhorn Storage"
  kubectl create namespace longhorn-system || true
  helm install longhorn longhorn/longhorn --version 1.5.1 --namespace longhorn-system
  
  echo -e "${GREEN}Longhorn persistent storage system installed${NC}"
  echo -e "${YELLOW}Access the Longhorn UI through Rancher or by setting up an ingress${NC}"
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running Storage script directly"
  PS3='Select storage option: '
  options=("Longhorn" "Quit")
  
  select opt in "${options[@]}"; do
    case $opt in
      "Longhorn")
        install_longhorn
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