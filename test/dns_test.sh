#!/bin/bash

echo "=== DNS Resolution Test for dev.tese.io domains ==="
echo

# Get the node IP for nip.io testing
NODE_IP=$(hostname -I | awk '{print $1}')

# Test DNS resolution for each service
SERVICES=("grafana" "prometheus" "pgadmin" "rancher" "loki" "argocd" "minio" "traefik" "velero")

echo "Testing DNS resolution..."
for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.dev.tese.io"
    echo -n "  $DOMAIN: "
    
    # Test DNS resolution
    IP=$(dig +short $DOMAIN)
    if [[ -n "$IP" ]]; then
        echo "✓ Resolves to: $IP"
    else
        echo "✗ No resolution"
    fi
done

echo
echo "=== Testing nip.io DNS resolution ==="

for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.${NODE_IP}.nip.io"
    echo -n "  $DOMAIN: "
    
    # Test DNS resolution
    IP=$(dig +short $DOMAIN)
    if [[ -n "$IP" ]]; then
        echo "✓ Resolves to: $IP"
    else
        echo "✗ No resolution"
    fi
done

echo
echo "=== Testing HTTP connectivity (dev.tese.io) ==="

for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.dev.tese.io"
    URL="http://$DOMAIN"
    echo -n "  $URL: "
    
    # Test HTTP connectivity
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|307|401)
            echo "✓ HTTP $HTTP_CODE (accessible)"
            ;;
        000)
            echo "✗ Connection failed (timeout/refused)"
            ;;
        *)
            echo "? HTTP $HTTP_CODE"
            ;;
    esac
done

echo
echo "=== Testing HTTP connectivity (nip.io) ==="

for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.${NODE_IP}.nip.io"
    URL="http://$DOMAIN"
    echo -n "  $URL: "
    
    # Test HTTP connectivity
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|307|401)
            echo "✓ HTTP $HTTP_CODE (accessible)"
            ;;
        000)
            echo "✗ Connection failed (timeout/refused)"
            ;;
        *)
            echo "? HTTP $HTTP_CODE"
            ;;
    esac
done

echo
echo "=== Testing HTTPS connectivity (dev.tese.io) ==="

for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.dev.tese.io"
    URL="https://$DOMAIN"
    echo -n "  $URL: "
    
    # Test HTTPS connectivity
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 -k "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|307|401)
            echo "✓ HTTPS $HTTP_CODE (accessible)"
            ;;
        000)
            echo "✗ Connection failed (timeout/refused)"
            ;;
        *)
            echo "? HTTPS $HTTP_CODE"
            ;;
    esac
done

echo
echo "=== ArgoCD Specific Tests ==="

echo "Testing ArgoCD UI accessibility:"
echo -n "  http://argocd.dev.tese.io: "
ARGOCD_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "http://argocd.dev.tese.io" 2>/dev/null)
if [[ "$ARGOCD_CODE" == "307" ]]; then
    echo "✓ HTTP $ARGOCD_CODE (ArgoCD redirect - UI accessible)"
elif [[ "$ARGOCD_CODE" =~ ^(200|302|401)$ ]]; then
    echo "✓ HTTP $ARGOCD_CODE (accessible)"
else
    echo "✗ HTTP $ARGOCD_CODE (not accessible)"
fi

echo -n "  http://argocd.${NODE_IP}.nip.io: "
ARGOCD_NIP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "http://argocd.${NODE_IP}.nip.io" 2>/dev/null)
if [[ "$ARGOCD_NIP_CODE" == "307" ]]; then
    echo "✓ HTTP $ARGOCD_NIP_CODE (ArgoCD redirect - UI accessible)"
elif [[ "$ARGOCD_NIP_CODE" =~ ^(200|302|401)$ ]]; then
    echo "✓ HTTP $ARGOCD_NIP_CODE (accessible)"
else
    echo "✗ HTTP $ARGOCD_NIP_CODE (not accessible)"
fi

echo
echo "=== Public IP Check ==="
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
echo "Server public IP: $PUBLIC_IP"
echo "Expected IP from Route53: 65.109.113.80"

if [[ "$PUBLIC_IP" == "65.109.113.80" ]]; then
    echo "✓ IP addresses match"
else
    echo "✗ IP addresses don't match!"
fi

echo
echo "=== Summary ==="
echo "Node IP: $NODE_IP"
echo "ArgoCD URLs tested:"
echo "  - http://argocd.dev.tese.io (HTTP $ARGOCD_CODE)"
echo "  - http://argocd.${NODE_IP}.nip.io (HTTP $ARGOCD_NIP_CODE)"
echo
echo "Note: HTTP 307 for ArgoCD indicates the UI is working and redirecting to login page" 