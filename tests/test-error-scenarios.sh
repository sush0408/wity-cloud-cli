#!/bin/bash

# Test script for error scenarios and recovery
# This script tests how the system handles various error conditions

echo "Testing Error Scenarios and Recovery"
echo "===================================="

# Source common functions
cd "$(dirname "$0")/.."
source "./common.sh"

echo -e "\n${YELLOW}1. Testing with missing KUBECONFIG:${NC}"
unset KUBECONFIG
if check_kubectl; then
    echo -e "${GREEN}✓ kubectl check handled missing KUBECONFIG${NC}"
else
    echo -e "${YELLOW}⚠ kubectl check failed as expected${NC}"
fi

echo -e "\n${YELLOW}2. Restoring environment:${NC}"
setup_k8s_env
if check_kubectl; then
    echo -e "${GREEN}✓ Environment restored successfully${NC}"
else
    echo -e "${RED}✗ Failed to restore environment${NC}"
fi

echo -e "\n${YELLOW}3. Testing Helm release detection:${NC}"
if helm_release_exists "longhorn" "longhorn-system"; then
    echo -e "${GREEN}✓ Detected existing Longhorn installation${NC}"
else
    echo -e "${YELLOW}⚠ Longhorn not detected (may not be installed)${NC}"
fi

echo -e "\n${YELLOW}4. Testing namespace detection:${NC}"
if namespace_exists "kube-system"; then
    echo -e "${GREEN}✓ Detected kube-system namespace${NC}"
else
    echo -e "${RED}✗ Failed to detect kube-system namespace${NC}"
fi

echo -e "\n${YELLOW}5. Testing non-existent namespace:${NC}"
if namespace_exists "non-existent-namespace-12345"; then
    echo -e "${RED}✗ False positive: detected non-existent namespace${NC}"
else
    echo -e "${GREEN}✓ Correctly identified non-existent namespace${NC}"
fi

echo -e "\n${YELLOW}6. Testing deployment wait function:${NC}"
if wait_for_deployment "coredns" "kube-system" "30"; then
    echo -e "${GREEN}✓ CoreDNS deployment is ready${NC}"
else
    echo -e "${YELLOW}⚠ CoreDNS deployment not ready within timeout${NC}"
fi

echo -e "\n${YELLOW}7. Testing cluster connectivity:${NC}"
if kubectl get nodes &>/dev/null; then
    echo -e "${GREEN}✓ Cluster is accessible${NC}"
    echo -e "Node count: $(kubectl get nodes --no-headers | wc -l)"
else
    echo -e "${RED}✗ Cannot access cluster${NC}"
fi

echo -e "\n${GREEN}Error scenario testing completed!${NC}"
echo -e "${YELLOW}Review the results above to ensure error handling is working correctly.${NC}" 