#!/bin/bash

echo "=== Final Fix for Remaining Issues ==="
echo

# Fix Loki ingress - it should point to loki namespace, not default
echo "----------------------------------------"
echo "Fixing Loki ingress"
echo "----------------------------------------"

# Delete the incorrect loki ingress in default namespace
kubectl delete ingress loki-ingress -n default --ignore-not-found=true

# Create correct loki ingress in loki namespace
NODE_IP=$(hostname -I | awk '{print $1}')

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: loki-ingress
  namespace: loki
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: loki.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki
            port:
              number: 3100
  - host: loki.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki
            port:
              number: 3100
EOF

echo "✓ Created Loki ingress in correct namespace (loki)"

# Fix PgAdmin ingress - ensure it's properly configured
echo
echo "----------------------------------------"
echo "Fixing PgAdmin ingress"
echo "----------------------------------------"

# Check current PgAdmin ingress
kubectl get ingress pgadmin-ingress -n pgadmin -o yaml > /tmp/pgadmin-ingress-backup.yaml

# Recreate PgAdmin ingress cleanly
kubectl delete ingress pgadmin-ingress -n pgadmin

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pgadmin-ingress
  namespace: pgadmin
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - host: pgadmin.dev.tese.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
  - host: pgadmin.${NODE_IP}.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pgadmin
            port:
              number: 80
EOF

echo "✓ Recreated PgAdmin ingress cleanly"

# Wait a moment for ingresses to be processed
echo
echo "Waiting 10 seconds for ingresses to be processed..."
sleep 10

# Test all services
echo
echo "=== Testing All Services ==="

SERVICES=("grafana" "prometheus" "pgadmin" "rancher" "loki")

for SERVICE in "${SERVICES[@]}"; do
    URL="http://${SERVICE}.dev.tese.io"
    echo -n "Testing $URL: "
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 "$URL" 2>/dev/null)
    
    case $HTTP_CODE in
        200|302|401)
            echo "✅ HTTP $HTTP_CODE (accessible)"
            ;;
        000)
            echo "❌ Connection failed"
            ;;
        404)
            echo "⚠️  HTTP 404 (ingress not found)"
            ;;
        *)
            echo "❓ HTTP $HTTP_CODE"
            ;;
    esac
done

echo
echo "=== Current Ingress Status ==="
kubectl get ingress --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTS:.spec.rules[*].host,ADDRESS:.status.loadBalancer.ingress[0].ip"

echo
echo "=== Access Summary ==="
echo "All services should now be accessible via both domains:"
echo
for SERVICE in "${SERVICES[@]}"; do
    echo "🌐 $SERVICE:"
    echo "   - http://${SERVICE}.dev.tese.io"
    echo "   - http://${SERVICE}.${NODE_IP}.nip.io"
    echo
done

echo "📝 Note: If any service still shows 404, check that the backend service exists and has endpoints." 