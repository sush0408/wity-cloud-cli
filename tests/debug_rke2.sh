#!/bin/bash

# RKE2 Debug and Fix Script
# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}==> RKE2 Cluster Diagnostic${NC}"

# Check if RKE2 server is running
echo -e "\n${YELLOW}1. RKE2 Server Status:${NC}"
if systemctl is-active --quiet rke2-server; then
    echo -e "${GREEN}✓ RKE2 server is running${NC}"
else
    echo -e "${RED}✗ RKE2 server is not running${NC}"
    echo -e "${YELLOW}Attempting to start RKE2 server...${NC}"
    systemctl start rke2-server
    sleep 10
fi

# Check RKE2 logs
echo -e "\n${YELLOW}2. Recent RKE2 logs:${NC}"
journalctl -u rke2-server --no-pager -l -n 10

# Check if binaries exist
echo -e "\n${YELLOW}3. RKE2 Binary Check:${NC}"
if [[ -f /var/lib/rancher/rke2/bin/kubectl ]]; then
    echo -e "${GREEN}✓ kubectl binary exists${NC}"
else
    echo -e "${RED}✗ kubectl binary not found${NC}"
fi

if [[ -f /var/lib/rancher/rke2/bin/helm ]]; then
    echo -e "${GREEN}✓ helm binary exists${NC}"
else
    echo -e "${RED}✗ helm binary not found${NC}"
fi

# Check kubeconfig
echo -e "\n${YELLOW}4. Kubeconfig Check:${NC}"
if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
    echo -e "${GREEN}✓ Kubeconfig file exists${NC}"
    ls -la /etc/rancher/rke2/rke2.yaml
else
    echo -e "${RED}✗ Kubeconfig file not found${NC}"
fi

# Set up environment
echo -e "\n${YELLOW}5. Setting up environment...${NC}"
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Test kubectl access
echo -e "\n${YELLOW}6. Testing kubectl access:${NC}"
if kubectl get nodes &> /dev/null; then
    echo -e "${GREEN}✓ kubectl can access cluster${NC}"
    kubectl get nodes -o wide
else
    echo -e "${RED}✗ kubectl cannot access cluster${NC}"
    echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
    sleep 30
    if kubectl get nodes &> /dev/null; then
        echo -e "${GREEN}✓ kubectl access restored${NC}"
        kubectl get nodes -o wide
    else
        echo -e "${RED}✗ Cluster still not accessible${NC}"
        echo -e "${YELLOW}Please check RKE2 installation${NC}"
    fi
fi

# Check system resources
echo -e "\n${YELLOW}7. System Resources:${NC}"
echo "Memory:"
free -h
echo -e "\nDisk:"
df -h
echo -e "\nLoad Average:"
uptime

# Check for common issues
echo -e "\n${YELLOW}8. Common Issue Checks:${NC}"

# Check if firewall is blocking
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        echo -e "${YELLOW}⚠ UFW firewall is active - may block cluster communication${NC}"
    fi
fi

# Check for SELinux
if command -v getenforce &> /dev/null; then
    if [[ "$(getenforce)" != "Disabled" ]]; then
        echo -e "${YELLOW}⚠ SELinux is enabled - may cause issues${NC}"
    fi
fi

# Create environment setup script
echo -e "\n${YELLOW}9. Creating environment setup script...${NC}"
cat > /root/setup-k8s-env.sh << 'EOF'
#!/bin/bash
# RKE2 Environment Setup
export PATH=$PATH:/var/lib/rancher/rke2/bin
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Add to bashrc if not already there
if ! grep -q "rancher/rke2/bin" ~/.bashrc; then
    echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc
    echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> ~/.bashrc
fi

echo "RKE2 environment configured"
echo "Current kubectl version:"
kubectl version --client --short 2>/dev/null || echo "kubectl not accessible"
EOF

chmod +x /root/setup-k8s-env.sh
echo -e "${GREEN}✓ Environment setup script created at /root/setup-k8s-env.sh${NC}"

echo -e "\n${YELLOW}==> Run 'source /root/setup-k8s-env.sh' to set up your environment${NC}"