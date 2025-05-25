#!/bin/bash

# Test script for batch mode functionality
# This script tests the automatic handling of existing installations

echo "Testing Batch Mode Functionality"
echo "================================="

# Source common functions
cd "$(dirname "$0")/.."
source "./common.sh"

echo -e "\n${YELLOW}Setting up test environment...${NC}"
export BATCH_MODE=true

echo -e "\n${YELLOW}Testing batch mode with existing installations:${NC}"

echo -e "\n${BLUE}1. Testing Longhorn (should detect existing and skip):${NC}"
install_longhorn

echo -e "\n${BLUE}2. Testing PostgreSQL (should handle existing gracefully):${NC}"
install_postgres_bitnami

echo -e "\n${BLUE}3. Testing cert-manager (should handle existing gracefully):${NC}"
install_cert_manager

echo -e "\n${YELLOW}Disabling batch mode...${NC}"
export BATCH_MODE=false

echo -e "\n${GREEN}Batch mode testing completed!${NC}"
echo -e "${YELLOW}All existing installations should have been handled automatically.${NC}" 