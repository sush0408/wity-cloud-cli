#!/bin/bash

echo "🔍 === COMPREHENSIVE LOKI DEBUGGING ==="
echo "Date: $(date)"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function section() {
    echo -e "\n${BLUE}==> $1${NC}"
}

section "1. Checking Loki Namespace and Resources"

echo -e "${YELLOW}Loki namespace status:${NC}"
kubectl get namespace loki 2>/dev/null || echo "❌ Loki namespace does not exist"

echo -e "\n${YELLOW}All resources in loki namespace:${NC}"
kubectl get all -n loki 2>/dev/null || echo "❌ No resources found or namespace doesn't exist"

echo -e "\n${YELLOW}Loki pods detailed status:${NC}"
kubectl get pods -n loki -o wide 2>/dev/null || echo "❌ No pods found"

echo -e "\n${YELLOW}Loki services:${NC}"
kubectl get svc -n loki 2>/dev/null || echo "❌ No services found"

echo -e "\n${YELLOW}Loki ingresses:${NC}"
kubectl get ingress -n loki 2>/dev/null || echo "❌ No ingresses found"

section "2. Checking Loki Installation Status"

echo -e "${YELLOW}Checking if Loki is installed via Helm:${NC}"
helm list -n loki 2>/dev/null || echo "❌ No Helm releases found in loki namespace"

echo -e "\n${YELLOW}Checking Loki in all namespaces:${NC}"
helm list --all-namespaces | grep loki || echo "❌ No Loki Helm releases found"

section "3. Loki Pod Logs and Health"

if kubectl get pods -n loki &>/dev/null; then
    echo -e "${YELLOW}Loki pod logs:${NC}"
    for pod in $(kubectl get pods -n loki -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        echo -e "\n--- Logs for pod: $pod ---"
        kubectl logs $pod -n loki --tail=20 2>/dev/null || echo "❌ Could not get logs for $pod"
    done
else
    echo -e "${RED}❌ No Loki pods found${NC}"
fi

section "4. Loki Service Endpoints"

if kubectl get svc loki -n loki &>/dev/null; then
    echo -e "${YELLOW}Loki service details:${NC}"
    kubectl describe svc loki -n loki
    
    echo -e "\n${YELLOW}Loki service endpoints:${NC}"
    kubectl get endpoints loki -n loki 2>/dev/null || echo "❌ No endpoints found"
else
    echo -e "${RED}❌ Loki service not found${NC}"
fi

section "5. Loki Ingress Analysis"

if kubectl get ingress loki-ingress -n loki &>/dev/null; then
    echo -e "${YELLOW}Loki ingress details:${NC}"
    kubectl describe ingress loki-ingress -n loki
    
    echo -e "\n${YELLOW}Loki ingress YAML:${NC}"
    kubectl get ingress loki-ingress -n loki -o yaml
else
    echo -e "${RED}❌ Loki ingress not found in loki namespace${NC}"
    
    echo -e "\n${YELLOW}Checking for Loki ingress in other namespaces:${NC}"
    kubectl get ingress --all-namespaces | grep loki || echo "❌ No Loki ingress found anywhere"
fi

section "6. Testing Loki Connectivity"

NODE_IP=$(hostname -I | awk '{print $1}')

echo -e "${YELLOW}Testing Loki service directly (port-forward):${NC}"
if kubectl get svc loki -n loki &>/dev/null; then
    echo "Starting port-forward to test Loki service..."
    kubectl port-forward svc/loki 3100:3100 -n loki &
    PORT_FORWARD_PID=$!
    sleep 5
    
    echo "Testing Loki health endpoint..."
    curl -s http://localhost:3100/ready || echo "❌ Loki health check failed"
    
    echo -e "\nTesting Loki metrics endpoint..."
    curl -s http://localhost:3100/metrics | head -5 || echo "❌ Loki metrics failed"
    
    echo -e "\nTesting Loki API..."
    curl -s http://localhost:3100/loki/api/v1/labels || echo "❌ Loki API failed"
    
    # Kill port-forward
    kill $PORT_FORWARD_PID 2>/dev/null
    wait $PORT_FORWARD_PID 2>/dev/null
else
    echo -e "${RED}❌ Cannot test - Loki service not found${NC}"
fi

echo -e "\n${YELLOW}Testing Loki via ingress:${NC}"
echo "Testing nip.io domain..."
curl -v -s http://loki.${NODE_IP}.nip.io/ready 2>&1 | head -10 || echo "❌ nip.io ingress test failed"

echo -e "\nTesting dev.tese.io domain..."
curl -v -s http://loki.dev.tese.io/ready 2>&1 | head -10 || echo "❌ dev.tese.io ingress test failed"

section "7. Loki Configuration Analysis"

if kubectl get pods -n loki &>/dev/null; then
    echo -e "${YELLOW}Loki configuration:${NC}"
    for pod in $(kubectl get pods -n loki -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        echo -e "\n--- Configuration for pod: $pod ---"
        kubectl exec $pod -n loki -- cat /etc/loki/local-config.yaml 2>/dev/null || echo "❌ Could not get config for $pod"
    done
else
    echo -e "${RED}❌ No Loki pods to check configuration${NC}"
fi

section "8. Traefik and Ingress Controller Status"

echo -e "${YELLOW}Checking Traefik status:${NC}"
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik 2>/dev/null || echo "❌ No Traefik pods found in kube-system"

echo -e "\n${YELLOW}Checking Traefik service:${NC}"
kubectl get svc -n kube-system -l app.kubernetes.io/name=traefik 2>/dev/null || echo "❌ No Traefik service found"

echo -e "\n${YELLOW}Checking if Traefik is in different namespace:${NC}"
kubectl get pods --all-namespaces | grep traefik || echo "❌ No Traefik pods found anywhere"

section "9. DNS Resolution Test"

echo -e "${YELLOW}Testing DNS resolution:${NC}"
echo -n "loki.${NODE_IP}.nip.io: "
dig +short loki.${NODE_IP}.nip.io || echo "❌ DNS resolution failed"

echo -n "loki.dev.tese.io: "
dig +short loki.dev.tese.io || echo "❌ DNS resolution failed"

section "10. Loki Storage and Persistence"

echo -e "${YELLOW}Checking Loki PVCs:${NC}"
kubectl get pvc -n loki 2>/dev/null || echo "❌ No PVCs found in loki namespace"

echo -e "\n${YELLOW}Checking storage class:${NC}"
kubectl get storageclass 2>/dev/null || echo "❌ No storage classes found"

section "11. Recommendations and Next Steps"

echo -e "${YELLOW}Based on the analysis above, here are the potential issues and solutions:${NC}"
echo

# Check if Loki is installed
if ! kubectl get namespace loki &>/dev/null; then
    echo -e "${RED}🔥 CRITICAL: Loki namespace doesn't exist${NC}"
    echo "   Solution: Install Loki using the monitoring script"
    echo "   Command: ./monitoring.sh -> Select 'Loki + Promtail'"
elif ! kubectl get pods -n loki &>/dev/null; then
    echo -e "${RED}🔥 CRITICAL: No Loki pods found${NC}"
    echo "   Solution: Reinstall Loki or check Helm deployment"
elif ! kubectl get svc loki -n loki &>/dev/null; then
    echo -e "${RED}🔥 CRITICAL: Loki service not found${NC}"
    echo "   Solution: Check Loki deployment and service configuration"
elif ! kubectl get ingress loki-ingress -n loki &>/dev/null; then
    echo -e "${YELLOW}⚠️  WARNING: Loki ingress not found${NC}"
    echo "   Solution: Create Loki ingress"
    echo "   Command: ./monitoring.sh -> Select 'Setup Loki Ingress'"
else
    echo -e "${GREEN}✅ Loki components appear to be present${NC}"
    echo "   The issue might be in configuration or connectivity"
    echo "   Check the logs and connectivity tests above for clues"
fi

echo
echo -e "${BLUE}🔧 Quick Fix Commands:${NC}"
echo "1. Reinstall Loki: ./monitoring.sh -> 'Loki + Promtail'"
echo "2. Setup Loki Ingress: ./monitoring.sh -> 'Setup Loki Ingress'"
echo "3. Test Loki directly: kubectl port-forward svc/loki 3100:3100 -n loki"
echo "4. Check Loki logs: kubectl logs -n loki -l app=loki"
echo "5. Cleanup certificates: ./monitoring.sh -> 'Cleanup Failed Certificates'"

echo
echo -e "${GREEN}🎯 Debug completed! Check the analysis above for issues.${NC}" 