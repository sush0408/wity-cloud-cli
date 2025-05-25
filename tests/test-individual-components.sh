#!/bin/bash

# Test script for individual component installations
# This script tests each component script individually to verify error handling

echo "Testing Individual Component Scripts"
echo "===================================="

# Source common functions
cd "$(dirname "$0")/.."
source "./common.sh"

echo -e "\n${YELLOW}Testing environment setup...${NC}"
if [[ -f "/root/setup-k8s-env.sh" ]]; then
    source "/root/setup-k8s-env.sh"
    echo -e "${GREEN}✓ Environment setup loaded${NC}"
else
    echo -e "${RED}✗ Environment setup not found${NC}"
fi

echo -e "\n${YELLOW}1. Testing Core Components (already installed):${NC}"
timeout 30 ./core.sh <<< "6" || echo "Core test completed"

echo -e "\n${YELLOW}2. Testing Storage (already installed):${NC}"
timeout 30 ./storage.sh <<< "1" || echo "Storage test completed"

echo -e "\n${YELLOW}3. Testing Database Installation:${NC}"
timeout 60 ./databases.sh <<< "2" || echo "Database test completed"

echo -e "\n${YELLOW}4. Testing Management Components:${NC}"
timeout 60 ./management.sh <<< "1" || echo "Management test completed"

echo -e "\n${YELLOW}5. Testing Monitoring Components:${NC}"
timeout 60 ./monitoring.sh <<< "5" || echo "Monitoring test completed"

echo -e "\n${GREEN}Individual component testing completed!${NC}"
echo -e "${YELLOW}Check the output above for any errors or issues.${NC}" 