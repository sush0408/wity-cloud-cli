#!/bin/bash

echo "=== DNS Resolution Test for dev.tese.io domains ==="
echo

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
echo "=== Testing HTTP connectivity ==="

for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.dev.tese.io"
    URL="http://$DOMAIN"
    echo -n "  $URL: "
    
    # Test HTTP connectivity
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|401)
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
echo "=== Testing HTTPS connectivity ==="

for SERVICE in "${SERVICES[@]}"; do
    DOMAIN="${SERVICE}.dev.tese.io"
    URL="https://$DOMAIN"
    echo -n "  $URL: "
    
    # Test HTTPS connectivity
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 -k "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|401)
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
echo "=== Public IP Check ==="
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com)
echo "Server public IP: $PUBLIC_IP"
echo "Expected IP from Route53: 65.109.113.80"

if [[ "$PUBLIC_IP" == "65.109.113.80" ]]; then
    echo "✓ IP addresses match"
else
    echo "✗ IP addresses don't match!"
fi 