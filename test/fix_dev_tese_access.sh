#!/bin/bash

echo "=== Fixing dev.tese.io Access Issues ==="
echo

# Services and their namespaces
declare -A SERVICE_NAMESPACES=(
    ["grafana"]="monitoring"
    ["prometheus"]="monitoring"
    ["pgadmin"]="pgadmin"
    ["rancher"]="cattle-system"
    ["loki"]="default"
)

# Service backend configurations
declare -A SERVICE_BACKENDS=(
    ["grafana"]="kube-prometheus-stack-grafana:80"
    ["prometheus"]="kube-prometheus-stack-prometheus:9090"
    ["pgadmin"]="pgadmin:80"
    ["rancher"]="rancher:80"
    ["loki"]="loki:3100"
)

NODE_IP=$(hostname -I | awk '{print $1}')

for SERVICE in "${!SERVICE_NAMESPACES[@]}"; do
    NAMESPACE="${SERVICE_NAMESPACES[$SERVICE]}"
    BACKEND="${SERVICE_BACKENDS[$SERVICE]}"
    BACKEND_NAME=$(echo $BACKEND | cut -d: -f1)
    BACKEND_PORT=$(echo $BACKEND | cut -d: -f2)
    
    echo "----------------------------------------"
    echo "Fixing $SERVICE in namespace $NAMESPACE"
    echo "----------------------------------------"
    
    # Check if ingress exists
    if kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" &>/dev/null; then
        echo "✓ Found existing ingress: ${SERVICE}-ingress"
        
        # Remove TLS configuration if it exists
        echo "  Removing TLS configuration..."
        kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p='[{"op": "remove", "path": "/spec/tls"}]' 2>/dev/null || echo "  No TLS to remove"
        
        # Remove HTTPS redirect middleware
        echo "  Removing HTTPS redirect middleware..."
        kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p='[{"op": "remove", "path": "/metadata/annotations/traefik.ingress.kubernetes.io~1router.middlewares"}]' 2>/dev/null || echo "  No middleware to remove"
        
        # Ensure web entrypoint is set
        echo "  Setting web entrypoint..."
        kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p='[{"op": "add", "path": "/metadata/annotations/traefik.ingress.kubernetes.io~1router.entrypoints", "value": "web"}]'
        
        # Ensure ingressClassName is set
        echo "  Setting ingress class..."
        kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p='[{"op": "add", "path": "/spec/ingressClassName", "value": "traefik"}]'
        
        # Check if dev.tese.io host exists
        HOSTS=$(kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[*].host}')
        if [[ "$HOSTS" == *"${SERVICE}.dev.tese.io"* ]]; then
            echo "  ✓ dev.tese.io host already configured"
        else
            echo "  Adding dev.tese.io host..."
            kubectl patch ingress "${SERVICE}-ingress" -n "$NAMESPACE" --type='json' -p="[{
                \"op\": \"add\",
                \"path\": \"/spec/rules/-\",
                \"value\": {
                    \"host\": \"${SERVICE}.dev.tese.io\",
                    \"http\": {
                        \"paths\": [{
                            \"path\": \"/\",
                            \"pathType\": \"Prefix\",
                            \"backend\": {
                                \"service\": {
                                    \"name\": \"${BACKEND_NAME}\",
                                    \"port\": {
                                        \"number\": ${BACKEND_PORT}
                                    }
                                }
                            }
                        }]
                    }
                }
            }]"
        fi
        
    else
        echo "✗ No ingress found, creating new one..."
        
        # Create new ingress with both hosts
        cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${SERVICE}-ingress
  namespace: ${NAMESPACE}
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: ${SERVICE}.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${BACKEND_NAME}
            port:
              number: ${BACKEND_PORT}
  - host: ${SERVICE}.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${BACKEND_NAME}
            port:
              number: ${BACKEND_PORT}
EOF
        echo "  ✓ Created new ingress with both hosts"
    fi
    
    # Clean up related certificates and secrets
    echo "  Cleaning up certificates and secrets..."
    kubectl delete certificate "${SERVICE}-tls" -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete certificaterequest "${SERVICE}-tls-1" -n "$NAMESPACE" --ignore-not-found=true
    kubectl delete secret "${SERVICE}-tls-secret" -n "$NAMESPACE" --ignore-not-found=true
    
    echo "  ✓ $SERVICE configuration updated"
    echo
done

# Clean up any remaining ACME solver ingresses
echo "Cleaning up ACME solver ingresses..."
kubectl delete ingress --all-namespaces -l acme.cert-manager.io/http01-solver=true --ignore-not-found=true

echo
echo "=== Testing dev.tese.io access ==="
sleep 5  # Give ingress a moment to update

for SERVICE in "${!SERVICE_NAMESPACES[@]}"; do
    URL="http://${SERVICE}.dev.tese.io"
    echo -n "Testing $URL: "
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|401)
            echo "✓ HTTP $HTTP_CODE (accessible)"
            ;;
        000)
            echo "✗ Connection failed"
            ;;
        *)
            echo "? HTTP $HTTP_CODE"
            ;;
    esac
done

echo
echo "=== Final Status ==="
echo "All services should now be accessible via:"
for SERVICE in "${!SERVICE_NAMESPACES[@]}"; do
    echo "  - http://${SERVICE}.dev.tese.io"
    echo "  - http://${SERVICE}.${NODE_IP}.nip.io"
done 