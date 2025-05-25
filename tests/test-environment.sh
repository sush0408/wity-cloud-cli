#!/bin/bash

# Test script for environment setup and kubectl functionality

echo "Testing Environment Setup"
echo "========================="

# Source common functions
cd "$(dirname "$0")/.."
source "./common.sh"

echo -e "\n${YELLOW}1. Testing environment setup script creation:${NC}"
create_setup_script

echo -e "\n${YELLOW}2. Testing environment loading:${NC}"
if [[ -f "/root/setup-k8s-env.sh" ]]; then
    source "/root/setup-k8s-env.sh"
    echo -e "${GREEN}✓ Environment setup script loaded${NC}"
else
    echo -e "${RED}✗ Environment setup script not found${NC}"
fi

echo -e "\n${YELLOW}3. Testing kubectl availability:${NC}"
if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}✓ kubectl found in PATH: $(which kubectl)${NC}"
else
    echo -e "${RED}✗ kubectl not found in PATH${NC}"
fi

echo -e "\n${YELLOW}4. Testing kubectl cluster access:${NC}"
if kubectl get nodes &> /dev/null; then
    echo -e "${GREEN}✓ kubectl can access cluster${NC}"
    kubectl get nodes
else
    echo -e "${RED}✗ kubectl cannot access cluster${NC}"
fi

echo -e "\n${YELLOW}5. Testing KUBECONFIG:${NC}"
echo -e "KUBECONFIG: ${KUBECONFIG:-'Not set'}"

echo -e "\n${YELLOW}6. Testing PATH:${NC}"
echo -e "PATH contains RKE2 binaries: $(echo $PATH | grep -q '/var/lib/rancher/rke2/bin' && echo 'Yes' || echo 'No')"

echo -e "\n${YELLOW}7. Testing cluster status:${NC}"
if kubectl get pods -A | head -10; then
    echo -e "${GREEN}✓ Cluster is accessible and has running pods${NC}"
else
    echo -e "${RED}✗ Cannot retrieve cluster pod information${NC}"
fi

echo -e "\n${GREEN}Environment testing completed!${NC}" 