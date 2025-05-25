#!/bin/bash

echo "=== Ingress Configuration Debug ==="
echo

echo "=== All Ingresses Overview ==="
kubectl get ingress --all-namespaces -o wide

echo
echo "=== Detailed Ingress Analysis ==="

# Check each service ingress
SERVICES=("grafana" "prometheus" "pgadmin" "rancher" "loki")
NAMESPACES=("monitoring" "monitoring" "pgadmin" "cattle-system" "default")

for i in "${!SERVICES[@]}"; do
    SERVICE="${SERVICES[$i]}"
    NAMESPACE="${NAMESPACES[$i]}"
    
    echo "----------------------------------------"
    echo "Service: $SERVICE (namespace: $NAMESPACE)"
    echo "----------------------------------------"
    
    # Check if ingress exists
    if kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" &>/dev/null; then
        echo "✓ Ingress exists: ${SERVICE}-ingress"
        
        # Get ingress details
        echo
        echo "Hosts configured:"
        kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[*].host}' | tr ' ' '\n' | sed 's/^/  - /'
        
        echo
        echo "TLS configuration:"
        TLS=$(kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.tls}' 2>/dev/null)
        if [[ -n "$TLS" && "$TLS" != "null" ]]; then
            echo "  ⚠️  TLS is configured (may cause HTTPS redirect issues)"
            kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.tls}' | jq .
        else
            echo "  ✓ No TLS configuration (HTTP only)"
        fi
        
        echo
        echo "Annotations:"
        kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations}' | jq .
        
        echo
        echo "Backend service check:"
        BACKEND_SERVICE=$(kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
        BACKEND_PORT=$(kubectl get ingress "${SERVICE}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}')
        
        if kubectl get svc "$BACKEND_SERVICE" -n "$NAMESPACE" &>/dev/null; then
            echo "  ✓ Backend service exists: $BACKEND_SERVICE:$BACKEND_PORT"
            
            # Check if service has endpoints
            ENDPOINTS=$(kubectl get endpoints "$BACKEND_SERVICE" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
            if [[ -n "$ENDPOINTS" ]]; then
                echo "  ✓ Service has endpoints: $ENDPOINTS"
            else
                echo "  ✗ Service has no endpoints (no pods ready)"
            fi
        else
            echo "  ✗ Backend service not found: $BACKEND_SERVICE"
        fi
        
    else
        echo "✗ No ingress found: ${SERVICE}-ingress"
        
        # Check if there's an ingress with different name
        echo "Checking for other ingresses in namespace $NAMESPACE:"
        kubectl get ingress -n "$NAMESPACE" 2>/dev/null | grep -v "NAME" | sed 's/^/  /'
    fi
    
    echo
done

echo "=== Traefik Status ==="
echo "Traefik pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

echo
echo "Traefik service:"
kubectl get svc -n kube-system -l app.kubernetes.io/name=traefik

echo
echo "=== Certificate Issues ==="
echo "Failed certificates:"
kubectl get certificates --all-namespaces | grep -v "True" | grep -v "NAME"

echo
echo "Certificate requests:"
kubectl get certificaterequests --all-namespaces | grep -v "True" | grep -v "NAME"

echo
echo "=== ACME Solver Ingresses (should be cleaned up) ==="
kubectl get ingress --all-namespaces -l acme.cert-manager.io/http01-solver=true 2>/dev/null || echo "None found (good)" 