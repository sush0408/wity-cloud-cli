# Wity Cloud Deploy Documentation

This directory contains comprehensive documentation for the Wity Cloud Deploy framework and its components.

## 📚 Documentation Index

### Database Deployments

- **[Percona MongoDB Deployment Guide](PERCONA_MONGODB_README.md)** - Complete guide for deploying Percona MongoDB with operator-based management, PMM monitoring, and automated backups

### Tools and Utilities

- **[kubectl-ai Documentation](kubectl.ai.md)** - Information about the kubectl-ai tool integration

## 🚀 Quick Start Guides

### Database Deployment Options

| Database | Deployment Method | Documentation |
|----------|------------------|---------------|
| **Percona MongoDB** | Operator-based with sharding | [Percona MongoDB Guide](PERCONA_MONGODB_README.md) |
| **PostgreSQL** | Bitnami Helm Chart | Run `./databases.sh` |
| **MySQL** | Bitnami Helm Chart | Run `./databases.sh` |
| **Redis** | Bitnami Helm Chart | Run `./databases.sh` |
| **MariaDB** | Bitnami Helm Chart | Run `./databases.sh` |

### Monitoring Solutions

| Component | Purpose | Access Method |
|-----------|---------|---------------|
| **PMM Server** | Percona database monitoring | `kubectl port-forward svc/pmm-server 8080:80 -n monitoring` |
| **Prometheus** | Metrics collection | Run `./monitoring.sh` |
| **Grafana** | Visualization dashboards | Run `./monitoring.sh` |
| **Loki** | Log aggregation | Run `./monitoring.sh` |

## 🏗️ Architecture Overview

### Percona MongoDB Architecture

The Percona MongoDB deployment provides a production-ready, sharded MongoDB cluster:

```
┌─────────────────────────────────────────────────────────────┐
│                    Percona MongoDB Cluster                  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Mongos    │  │   Mongos    │  │             │         │
│  │  (Router)   │  │  (Router)   │  │             │         │
│  └─────────────┘  └─────────────┘  │             │         │
│         │                 │        │   Config    │         │
│         └─────────┬───────┘        │   Servers   │         │
│                   │                │   (3 nodes) │         │
│  ┌────────────────┴──────────────┐ │             │         │
│  │                               │ └─────────────┘         │
│  │  ┌─────────────┐ ┌─────────────┐                       │
│  │  │   Shard 0   │ │   Shard 1   │                       │
│  │  │ (rs0 - 3    │ │ (rs1 - 3    │                       │
│  │  │  replicas)  │ │  replicas)  │                       │
│  │  └─────────────┘ └─────────────┘                       │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Monitoring Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Stack                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │     PMM     │  │  Prometheus │  │   Grafana   │         │
│  │   Server    │  │   Metrics   │  │ Dashboards  │         │
│  │             │  │ Collection  │  │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│         └─────────────────┼─────────────────┘              │
│                           │                                │
│  ┌─────────────────────────┴─────────────────────────────┐ │
│  │                    Loki                               │ │
│  │                Log Aggregation                        │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Configuration Management

### Environment Variables

Common environment variables used across deployments:

```bash
# Batch mode for non-interactive deployments
export BATCH_MODE=true

# Kubernetes configuration
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# PMM credentials (change in production)
export PMM_ADMIN_PASSWORD=admin-password
```

### Default Credentials

**MongoDB (Percona):**
- Database Admin: `databaseAdmin` / `databaseAdmin123456`
- User Admin: `userAdmin` / `userAdmin123456`
- Cluster Admin: `clusterAdmin` / `clusterAdmin123456`

**PMM Monitoring:**
- Username: `admin`
- Password: `admin-password`

**Other Databases:**
- PostgreSQL: `postgres` / `secretpassword`
- MySQL: `root` / `secretpassword`
- MariaDB: `root` / `secretpassword`

> ⚠️ **Security Note**: Change all default passwords in production environments!

## 📋 Common Commands

### Deployment Commands

```bash
# Complete Percona MongoDB stack
sudo ./percona-mongodb-deploy.sh

# Individual database deployments
sudo ./databases.sh

# Monitoring stack
sudo ./monitoring.sh

# Core Kubernetes setup
sudo ./core.sh
```

### Management Commands

```bash
# Check MongoDB cluster status
kubectl get psmdb -n pgo

# Check all pods
kubectl get pods --all-namespaces

# Access PMM dashboard
kubectl port-forward svc/pmm-server 8080:80 -n monitoring

# Access Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

### Troubleshooting Commands

```bash
# Check node resources
kubectl describe nodes

# Check persistent volumes
kubectl get pv,pvc --all-namespaces

# Check operator logs
kubectl logs -n pgo -l name=percona-server-mongodb-operator

# Debug specific pod
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

## 🔍 Troubleshooting Guide

### New Troubleshooting Tool

A comprehensive troubleshooting script is available to help diagnose and fix common deployment issues:

```bash
sudo ./troubleshoot.sh
```

**Available Options:**
1. **System Health Check** - Check resources, limits, and cluster connectivity
2. **Diagnose Cilium Issues** - Detect and resolve CNI conflicts  
3. **Fix Cilium Conflicts** - Automatically resolve RKE2/Helm Cilium conflicts
4. **Check Common Issues** - File limits, system parameters, stuck namespaces
5. **Collect System Information** - Generate comprehensive diagnostic report
6. **Full Diagnostic Run** - Run all checks and generate report

### Common Issues

1. **Cilium Installation Conflicts**
   - **Problem:** `Error: INSTALLATION FAILED: ServiceAccount "cilium" exists and cannot be imported`
   - **Solution:** Run `sudo ./troubleshoot.sh` and select "Fix Cilium Conflicts"
   - **Manual check:** Use `sudo ./core.sh` → "Check Cilium Status"

2. **"Too many open files" Error**
   - **Problem:** RKE2 installation fails with file limit errors
   - **Solution:** Run `sudo ./troubleshoot.sh` → "Check Common Issues"
   - **Prevention:** Run `sudo ./check-dependencies.sh` before deployment

3. **Pods stuck in Pending state**
   - Check node resources: `kubectl describe nodes`
   - Check storage: `kubectl get pv,pvc --all-namespaces`
   - Use troubleshooting tool: `sudo ./troubleshoot.sh` → "System Health Check"

4. **Operator not starting**
   - Verify CRDs: `kubectl get crd | grep percona`
   - Check operator logs: `kubectl logs -n pgo -l name=percona-server-mongodb-operator`
   - Run diagnostic: `sudo ./troubleshoot.sh` → "Full Diagnostic Run"

5. **Network connectivity issues**
   - Check services: `kubectl get svc --all-namespaces`
   - Verify ingress: `kubectl get ingress --all-namespaces`
   - Diagnose Cilium: `sudo ./troubleshoot.sh` → "Diagnose Cilium Issues"

### Recovery Procedures

1. **Restart failed deployments**
   ```bash
   kubectl delete pod <pod-name> -n <namespace>
   ```

2. **Clean up and redeploy**
   ```bash
   kubectl delete namespace <namespace>
   # Re-run deployment script
   ```

## 📖 Additional Resources

- [Percona Documentation](https://docs.percona.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [RKE2 Documentation](https://docs.rke2.io/)

## 🤝 Contributing

When adding new documentation:

1. Place component-specific docs in this `docs/` directory
2. Update this index file with links to new documentation
3. Follow the existing documentation structure and formatting
4. Include practical examples and troubleshooting information

## 📄 License

This documentation is part of the Wity Cloud Deploy project and follows the same licensing terms. 