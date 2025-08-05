
### GitHub :
https://github.com/8gears/n8n-helm-chart


helm install tese-n8n oci://8gears.container-registry.com/library/n8n --version 0.25.2


<!-- helm install tese-n8n oci://8gears.container-registry.com/library/n8n  --version 0.25.2  --namespace n8n  --values values.yaml --> doenst works


helm install -f n8n.yaml n8n oci://8gears.container-registry.com/library/n8n --namespace n8n

helm upgrade -f n8n.yaml n8n oci://8gears.container-registry.com/library/n8n --namespace n8n

helm uninstall n8n -n n8n 

kubectl exec -it n8n-bb489db96-dngph -n n8n -- env | grep N8N_



REtrive the encryption key in n8n 
kubectl exec -it -n n8n n8n-bb489db96-dngph -- cat /home/node/.n8n/config
{
        "encryptionKey": "IbPcm6M3bnr3SzSZcOK2MfqlaZJUrQXk"
}


export POD_NAME=$(kubectl get pods --namespace n8n -l "app.kubernetes.io/name=n8n,app.kubernetes.io/instance=n8n" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace n8n $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace n8n port-forward $POD_NAME 8080:$CONTAINER_PORT


### PostgreSQL Database Verification

# Check if n8n is using PostgreSQL or SQLite
kubectl exec -it -n n8n $(kubectl get pods -n n8n -o jsonpath="{.items[0].metadata.name}") -- find /home/node -name "*.sqlite" -o -name "*.db"
# If this returns a SQLite file (e.g., /home/node/.n8n/database.sqlite), n8n is using SQLite instead of PostgreSQL

# Check database environment variables in n8n pod
kubectl exec -it -n n8n $(kubectl get pods -n n8n -o jsonpath="{.items[0].metadata.name}") -- env | grep -i "DB_"

# Create PostgreSQL database for n8n if it doesn't exist
kubectl exec -it pgdb-postgresql-0 -n database -- psql -U postgres -c "CREATE DATABASE n8n_db;"

# List all databases in PostgreSQL
kubectl exec -it pgdb-postgresql-0 -n database -- psql -U postgres -c "\l"

# Check if n8n tables exist in PostgreSQL database
kubectl exec -it pgdb-postgresql-0 -n database -- psql -U postgres -d n8n_db -c "\dt"

# Check schema in PostgreSQL database
kubectl exec -it pgdb-postgresql-0 -n database -- psql -U postgres -d n8n_db -c "\dn"

# Check tables in public schema
kubectl exec -it pgdb-postgresql-0 -n database -- psql -U postgres -d n8n_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"


helm upgrade -f n8n.yaml n8n oci://8gears.container-registry.com/library/n8n --namespace n8n
Pulled: 8gears.container-registry.com/library/n8n:1.0.6
Digest: sha256:71f0e96d9ff823c4e52292a1e6e87b93a9167e95a2daa1d9066db96dab1771a9
Release "n8n" has been upgraded. Happy Helming!
NAME: n8n
LAST DEPLOYED: Mon Mar 31 13:53:46 2025
NAMESPACE: n8n
STATUS: deployed
REVISION: 3
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace n8n -l "app.kubernetes.io/name=n8n,app.kubernetes.io/instance=n8n" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace n8n $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace n8n port-forward $POD_NAME 8080:$CONTAINER_PORT
