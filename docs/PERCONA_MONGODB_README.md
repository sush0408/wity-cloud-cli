# Percona MongoDB Deployment Guide

This guide covers the enhanced Percona MongoDB deployment that has been integrated into the Wity Cloud Deploy framework. The deployment includes operator-based MongoDB clusters, PMM monitoring, automated backups, and production-ready configurations.

## Overview

The Percona MongoDB deployment provides:

- **Operator-based MongoDB clusters** with sharding support
- **PMM (Percona Monitoring and Management)** for comprehensive monitoring
- **Automated backup solutions** with local and S3 storage options
- **High availability** with replica sets and anti-affinity rules
- **Production-ready configurations** with resource limits and security

## Quick Start

### 1. Complete Stack Deployment

For a full deployment including all components:

```bash
sudo ./percona-mongodb-deploy.sh
# Select option 1: "Deploy Complete Stack"
```

### 2. MongoDB Only

To install just the MongoDB cluster:

```bash
sudo ./databases.sh
# Select option 1: "MongoDB (Percona Operator)"
```

### 3. PMM Monitoring Only

To install just the PMM monitoring server:

```bash
sudo ./monitoring.sh
# Select option: "Install PMM Server"
```

## Architecture

### MongoDB Cluster Configuration

The deployment creates a sharded MongoDB cluster with:

- **2 Shards (rs0, rs1)**: Each with 3 replica set members
- **3 Config Servers**: For metadata and configuration
- **2 Mongos Routers**: For query routing and load balancing
- **Anti-affinity rules**: To ensure high availability
- **Resource limits**: Optimized for production workloads

### Resource Allocation

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|-----------|-------------|-----------|----------------|--------------|---------|
| Shard Nodes | 500m | 1000m | 1G | 2G | 3Gi |
| Config Servers | 250m | 500m | 512M | 1G | 1Gi |
| Mongos Routers | 500m | 1000m | 512M | 1G | - |

### PMM Monitoring

- **PMM Server**: Centralized monitoring dashboard
- **Resource allocation**: 500m-2000m CPU, 1-4Gi memory
- **Storage**: 10Gi for metrics and logs
- **Access**: Web interface on port 80/443

## Configuration Files

The deployment creates several configuration files:

```
databases/mongodb/deployments/
├── mongo-secrets.yaml          # MongoDB user credentials
├── s3-credentials.yaml         # S3 backup credentials (optional)
├── backup-pvc.yaml            # Backup storage volume
└── mongodb-config.yaml        # Main cluster configuration

monitoring/pmm/
└── pmm-server.yaml            # PMM server deployment

infrastructure/k8s/metallb/
└── metallb-config.yaml        # Load balancer configuration
```

## Access Information

### MongoDB Connection

**Connection String:**
```
mongodb://databaseAdmin:databaseAdmin123456@psmdb-mongos.pgo.svc.cluster.local/admin
```

**Default Credentials:**
- **Database Admin**: `databaseAdmin` / `databaseAdmin123456`
- **User Admin**: `userAdmin` / `userAdmin123456`
- **Cluster Admin**: `clusterAdmin` / `clusterAdmin123456`
- **Backup User**: `backup` / `backup123456`

### PMM Monitoring

**Access PMM Dashboard:**
```bash
kubectl port-forward svc/pmm-server 8080:80 -n monitoring
```
Then visit: http://localhost:8080

**Credentials:**
- **Username**: `admin`
- **Password**: `admin-password`

## Backup Configuration

### Local Backups

Automated daily backups are configured by default:

- **Schedule**: Daily at midnight (0 0 * * *)
- **Storage**: Local filesystem (`/backups`)
- **Compression**: gzip with level 3
- **Retention**: Managed by Percona Backup for MongoDB

### S3 Backups (Optional)

To enable S3 backups, provide AWS credentials during deployment:

```bash
# During deployment, when prompted:
Enter AWS Access Key ID: YOUR_ACCESS_KEY
Enter AWS Secret Access Key: YOUR_SECRET_KEY
```

## Management Commands

### Check Cluster Status

```bash
# MongoDB cluster status
kubectl get psmdb -n pgo

# Pod status
kubectl get pods -n pgo

# PMM status
kubectl get pods -n monitoring -l app=pmm-server
```

### Debugging

```bash
# Describe MongoDB cluster
kubectl describe psmdb psmdb -n pgo

# Check pod logs
kubectl logs -n pgo <pod-name>

# Debug specific pod
kubectl describe pod -n pgo <pod-name>

# PMM logs
kubectl logs -n monitoring -l app=pmm-server
```

### Scaling Operations

```bash
# Edit cluster configuration
kubectl edit psmdb psmdb -n pgo

# Scale replica sets (modify the yaml and apply)
kubectl apply -f databases/mongodb/deployments/mongodb-config.yaml
```

## Security Considerations

### Production Deployment

For production environments, consider:

1. **Change default passwords**:
   ```bash
   # Update the secrets in mongo-secrets.yaml with new base64 encoded passwords
   kubectl apply -f databases/mongodb/deployments/mongo-secrets.yaml
   ```

2. **Enable TLS/SSL**:
   - Configure certificates in the MongoDB cluster spec
   - Update connection strings to use SSL

3. **Network policies**:
   - Implement Kubernetes network policies
   - Restrict access to MongoDB and PMM services

4. **RBAC**:
   - Review and customize service account permissions
   - Implement least-privilege access

### Backup Security

- **Encrypt backups** when using S3 storage
- **Rotate backup credentials** regularly
- **Monitor backup success** through PMM dashboards

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**:
   ```bash
   # Check node resources
   kubectl describe nodes
   
   # Check PVC status
   kubectl get pvc -n pgo
   ```

2. **Operator not starting**:
   ```bash
   # Check operator logs
   kubectl logs -n pgo -l name=percona-server-mongodb-operator
   
   # Verify CRDs
   kubectl get crd | grep percona
   ```

3. **PMM not accessible**:
   ```bash
   # Check PMM pod status
   kubectl get pods -n monitoring -l app=pmm-server
   
   # Check service
   kubectl get svc -n monitoring pmm-server
   ```

### Recovery Procedures

1. **Restore from backup**:
   ```bash
   # Create restore job (example)
   kubectl apply -f - <<EOF
   apiVersion: psmdb.percona.com/v1
   kind: PerconaServerMongoDBRestore
   metadata:
     name: restore-$(date +%s)
     namespace: pgo
   spec:
     clusterName: psmdb
     backupName: <backup-name>
   EOF
   ```

2. **Cluster recovery**:
   ```bash
   # Delete and recreate cluster
   kubectl delete psmdb psmdb -n pgo
   kubectl apply -f databases/mongodb/deployments/mongodb-config.yaml
   ```

## Integration with Existing Infrastructure

### With ArgoCD

The MongoDB deployment can be managed through ArgoCD:

1. Create ArgoCD application pointing to your Git repository
2. Include the MongoDB configuration files
3. Set up automated sync policies

### With Prometheus/Grafana

PMM integrates with existing monitoring:

1. Configure PMM to export metrics to Prometheus
2. Import PMM dashboards into Grafana
3. Set up alerting rules for MongoDB metrics

## Performance Tuning

### MongoDB Optimization

1. **Index optimization**: Monitor slow queries through PMM
2. **Sharding strategy**: Review shard key selection
3. **Connection pooling**: Configure application connection pools
4. **Read preferences**: Use appropriate read preferences for workload

### Kubernetes Optimization

1. **Node affinity**: Place MongoDB pods on dedicated nodes
2. **Storage classes**: Use high-performance storage classes
3. **Network policies**: Optimize network communication
4. **Resource quotas**: Set appropriate namespace quotas

## Maintenance

### Regular Tasks

1. **Monitor cluster health** through PMM dashboards
2. **Review backup success** and test restore procedures
3. **Update operator** to latest stable version
4. **Monitor resource usage** and scale as needed

### Updates

```bash
# Update operator
kubectl apply -f percona-server-mongodb-operator/deploy/crd.yaml
kubectl apply -f percona-server-mongodb-operator/deploy/operator.yaml

# Update cluster (modify image version in config)
kubectl apply -f databases/mongodb/deployments/mongodb-config.yaml
```

## Support and Documentation

- **Percona Documentation**: https://docs.percona.com/percona-operator-for-psmdb/
- **PMM Documentation**: https://docs.percona.com/percona-monitoring-and-management/
- **Kubernetes Documentation**: https://kubernetes.io/docs/

## License

This deployment configuration is part of the Wity Cloud Deploy project and follows the same licensing terms. 