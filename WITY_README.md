# Wity Cloud Deploy

A comprehensive Kubernetes deployment framework with enhanced database capabilities, monitoring solutions, and production-ready configurations.

## 🚀 Quick Start

### Prerequisites

- Ubuntu/Debian-based system (recommended)
- Root access or sudo privileges
- At least 4GB RAM and 20GB disk space
- Internet connectivity for downloading components

### 1. Check Dependencies

```bash
sudo ./check-dependencies.sh
```

This will install essential packages and optimize system parameters.

### 2. Deploy Core Kubernetes (RKE2)

```bash
sudo ./core.sh
# Select "All Core Components" for complete setup
```

### 3. Deploy Database Stack

For a complete Percona MongoDB deployment with monitoring:

```bash
sudo ./percona-mongodb-deploy.sh
# Select "Deploy Complete Stack"
```

Or choose individual databases:

```bash
sudo ./databases.sh
```

### 4. Add Monitoring (Optional)

```bash
sudo ./monitoring.sh
```

## 📚 Documentation

Complete documentation is available in the [docs/](docs/) folder:

- **[Percona MongoDB Guide](docs/PERCONA_MONGODB_README.md)** - Comprehensive MongoDB deployment guide
- **[Architecture Overview](docs/README.md)** - System architecture and configuration details
- **[kubectl-ai Integration](docs/kubectl.ai.md)** - AI-powered Kubernetes management

## 🛠️ Available Components

### Core Infrastructure

| Component | Script | Description |
|-----------|--------|-------------|
| **RKE2 Kubernetes** | `core.sh` | Lightweight Kubernetes distribution with Cilium CNI |
| **Helm** | `core.sh` | Package manager for Kubernetes |
| **MetalLB** | `core.sh` | Load balancer for bare metal |
| **cert-manager** | `core.sh` | Certificate management |

### Database Solutions

| Database | Method | Features |
|----------|--------|----------|
| **Percona MongoDB** | Operator-based | Sharding, PMM monitoring, automated backups |
| **PostgreSQL** | Helm chart | High availability, persistent storage |
| **MySQL** | Helm chart | Replication, backup support |
| **Redis** | Helm chart | Clustering, persistence |
| **MariaDB** | Helm chart | Galera clustering |

### Monitoring & Observability

| Component | Purpose | Access |
|-----------|---------|--------|
| **PMM Server** | Percona database monitoring | Port-forward 8080:80 |
| **Prometheus** | Metrics collection | Helm deployment |
| **Grafana** | Visualization | Port-forward 3000:80 |
| **Loki** | Log aggregation | Centralized logging |

### Cloud Integration

| Service | Script | Features |
|---------|--------|----------|
| **AWS CLI** | `aws.sh` | S3, ECR, Route53 integration |
| **Velero** | `backup.sh` | Kubernetes backup to S3 |
| **External DNS** | `networking.sh` | Automatic DNS management |

## 🔧 Troubleshooting

### New Troubleshooting Tool

We've added a comprehensive troubleshooting script to help diagnose and fix common issues:

```bash
sudo ./troubleshoot.sh
```

**Available Options:**
1. **System Health Check** - Check resources, limits, and cluster connectivity
2. **Diagnose Cilium Issues** - Detect and resolve CNI conflicts
3. **Fix Cilium Conflicts** - Automatically resolve RKE2/Helm Cilium conflicts
4. **Check Common Issues** - File limits, system parameters, stuck namespaces
5. **Collect System Information** - Generate diagnostic report
6. **Full Diagnostic Run** - Run all checks and generate report

### Common Issues and Solutions

#### 1. Cilium Installation Conflicts

**Problem:** Error during Cilium installation:
```
Error: INSTALLATION FAILED: ServiceAccount "cilium" exists and cannot be imported
```

**Solution:**
```bash
sudo ./troubleshoot.sh
# Select "Fix Cilium Conflicts"
```

Or manually check Cilium status:
```bash
sudo ./core.sh
# Select "Check Cilium Status"
```

#### 2. "Too many open files" Error

**Problem:** RKE2 installation fails with file limit errors.

**Solution:** The system is automatically optimized during installation, but you can manually fix:
```bash
sudo ./troubleshoot.sh
# Select "Check Common Issues"
```

#### 3. Pods Stuck in Pending State

**Problem:** Pods remain in Pending state after deployment.

**Diagnosis:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get nodes
kubectl get pv,pvc --all-namespaces
```

**Common Causes:**
- Insufficient resources
- Storage issues
- Node affinity problems

#### 4. MongoDB Cluster Not Starting

**Problem:** Percona MongoDB pods fail to start.

**Solution:**
```bash
# Check operator status
kubectl get pods -n pgo
kubectl logs -n pgo -l name=percona-server-mongodb-operator

# Check cluster status
kubectl get psmdb -n pgo
kubectl describe psmdb psmdb -n pgo
```

### System Requirements Issues

If you encounter resource-related problems:

```bash
# Check current resources
free -h
df -h
ulimit -a

# Apply optimizations
sudo ./check-dependencies.sh
```

## 🔐 Security & Access

### Default Credentials

**MongoDB (Percona):**
- Connection: `mongodb://databaseAdmin:databaseAdmin123456@psmdb-mongos.pgo.svc.cluster.local/admin`
- Database Admin: `databaseAdmin` / `databaseAdmin123456`

**PMM Monitoring:**
- URL: `http://localhost:8080` (after port-forward)
- Username: `admin` / Password: `admin-password`

**Other Databases:**
- PostgreSQL: `postgres` / `secretpassword`
- MySQL/MariaDB: `root` / `secretpassword`

> ⚠️ **Important:** Change all default passwords in production!

### Access Commands

```bash
# MongoDB access
kubectl port-forward svc/psmdb-mongos 27017:27017 -n pgo

# PMM monitoring
kubectl port-forward svc/pmm-server 8080:80 -n monitoring

# Grafana dashboard
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

## 🚀 Advanced Features

### Batch Mode Deployment

For automated deployments without interactive prompts:

```bash
export BATCH_MODE=true
sudo ./percona-mongodb-deploy.sh
```

### Custom Configurations

Modify configurations before deployment:

```bash
# Edit MongoDB cluster configuration
vim infrastructure/k8s/percona-mongodb/psmdb-cluster.yaml

# Edit monitoring settings
vim infrastructure/k8s/monitoring/pmm-server.yaml
```

### Backup Configuration

The Percona MongoDB deployment includes automated backups:

- **Local backups:** Daily snapshots stored in cluster
- **S3 backups:** Configure AWS credentials for remote storage
- **Retention:** Configurable retention policies

## 📊 Monitoring and Maintenance

### Health Checks

```bash
# Overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# Database-specific checks
kubectl get psmdb -n pgo
kubectl get pods -n pgo

# Monitoring stack
kubectl get pods -n monitoring
```

### Log Access

```bash
# MongoDB operator logs
kubectl logs -n pgo -l name=percona-server-mongodb-operator

# PMM server logs
kubectl logs -n monitoring -l app=pmm-server

# RKE2 system logs
journalctl -u rke2-server
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

If you encounter issues:

1. Run the troubleshooting tool: `sudo ./troubleshoot.sh`
2. Check the [documentation](docs/)
3. Collect system information for support
4. Open an issue with diagnostic details

---

**Note:** This framework is designed for development and testing environments. For production deployments, review and customize security settings, resource allocations, and backup strategies according to your requirements. 