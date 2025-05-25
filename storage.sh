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
  
  # Use safe installation
  safe_helm_install "longhorn" "longhorn/longhorn" "longhorn-system" \
    --set defaultSettings.defaultDataPath="/var/lib/longhorn/" \
    --set defaultSettings.replicaSoftAntiAffinity=false \
    --set defaultSettings.storageOverProvisioningPercentage=200 \
    --set defaultSettings.storageMinimalAvailablePercentage=25 \
    --set defaultSettings.upgradeChecker=false \
    --set defaultSettings.defaultReplicaCount=1 \
    --set defaultSettings.defaultLonghornStaticStorageClass=longhorn \
    --set defaultSettings.backupstorePollInterval=300 \
    --set defaultSettings.failedBackupTTL=1440 \
    --set defaultSettings.restoreVolumeRecurringJobs=false \
    --set defaultSettings.recurringSuccessfulJobsHistoryLimit=1 \
    --set defaultSettings.recurringFailedJobsHistoryLimit=1 \
    --set defaultSettings.supportBundleFailedHistoryLimit=1 \
    --set defaultSettings.taintToleration="CriticalAddonsOnly=true:NoSchedule" \
    --set defaultSettings.systemManagedComponentsNodeSelector="node-role.kubernetes.io/control-plane:true" \
    --set defaultSettings.guaranteedEngineManagerCPU=12 \
    --set defaultSettings.guaranteedReplicaManagerCPU=12
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}Longhorn storage installed successfully${NC}"
    echo -e "${YELLOW}Access the Longhorn UI through Rancher or by setting up an ingress${NC}"
  fi
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