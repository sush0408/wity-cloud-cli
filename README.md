# Wity Cloud CLI

**Wity Cloud CLI** is an open-source tool built by **[wityliti.io](https://wityliti.io)** to streamline the deployment, debugging, and monitoring of Kubernetes clusters—both on-prem and in hybrid cloud environments. This AI-augmented CLI provides a full-stack orchestration experience across networking, storage, observability, and multi-cloud integrations.

## 🚀 Why Wity Cloud CLI?

Wity Cloud CLI is purpose-built for:

* **Bare-metal Kubernetes clusters** (e.g., Hetzner, physical nodes)
* **AI-first DevOps workflows**
* Seamless **S3, ECR, Route53** integrations with AWS
* **Multi-namespace service readiness checks, logs, health reports, and TLS automation**
* Full support for **RKE2**, **Longhorn**, **Traefik**, **Cilium**, **Rancher**, and **KubeVirt**

## 🎯 Key Features

- **🚀 One-Command Deployment**: Complete stack deployment with single commands
- **🔧 Modular Architecture**: Deploy individual components or complete stacks
- **📊 Enterprise Monitoring**: Integrated PMM, Prometheus, Grafana, and Loki
- **🗄️ Production Databases**: Operator-based MongoDB, PostgreSQL, MySQL, Redis
- **🔄 GitOps Ready**: ArgoCD integration for continuous deployment
- **☁️ Cloud Native**: AWS integration, backup solutions, certificate management
- **🛠️ Intelligent Troubleshooting**: Automated diagnostics and conflict resolution
- **🤖 AI-Powered**: kubectl-ai integration for intelligent cluster management
- **📚 Comprehensive Documentation**: Detailed guides and troubleshooting resources
- **🔒 HTTPS Automation**: Automated Let's Encrypt certificates for all services

## 🚀 Quick Start

### Prerequisites

- **OS**: Ubuntu/Debian-based system (tested on Ubuntu 24.04)
- **Resources**: Minimum 4GB RAM, 20GB disk space (8GB+ RAM recommended for full stack)
- **Access**: Root privileges or sudo access
- **Network**: Internet connectivity for component downloads

### Installation

```bash
# Clone the repository
git clone https://github.com/wityliti/wity-cloud-cli.git
cd wity-cloud-cli

# Make executable and run
chmod +x wity-cloud-cli.sh
sudo ./wity-cloud-cli.sh
```

### Quick Deployment

```bash
# 1. System preparation
sudo ./check-dependencies.sh

# 2. Deploy Kubernetes core
sudo ./core.sh

# 3. Deploy complete database stack
sudo ./percona-mongodb-deploy.sh

# 4. Add CI/CD pipeline
sudo ./cicd.sh
```

## 🏗️ Architecture Overview

### Core Infrastructure Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Wity Cloud CLI                           │
├─────────────────────────────────────────────────────────────┤
│  Applications & CI/CD                                       │
│  ├── ArgoCD (GitOps)                                       │
│  ├── Sample Applications                                    │
│  └── Custom Workloads                                      │
├─────────────────────────────────────────────────────────────┤
│  Monitoring & Observability                                │
│  ├── PMM Server (Database Monitoring)                      │
│  ├── Prometheus + Grafana                                  │
│  ├── Loki (Log Aggregation)                               │
│  └── AlertManager                                          │
├─────────────────────────────────────────────────────────────┤
│  Database Layer                                            │
│  ├── Percona MongoDB (Sharded Cluster)                    │
│  ├── PostgreSQL (HA)                                      │
│  ├── MySQL/MariaDB                                        │
│  └── Redis                                                │
├─────────────────────────────────────────────────────────────┤
│  Networking & Security                                     │
│  ├── Traefik/Nginx Ingress                               │
│  ├── MetalLB (Load Balancer)                             │
│  ├── cert-manager (TLS)                                   │
│  └── Cilium CNI                                           │
├─────────────────────────────────────────────────────────────┤
│  Kubernetes Platform                                       │
│  ├── RKE2 (Lightweight Kubernetes)                        │
│  ├── Helm (Package Manager)                               │
│  └── kubectl + kubectl-ai                                 │
├─────────────────────────────────────────────────────────────┤
│  Infrastructure                                            │
│  ├── Ubuntu 24.04 LTS                                     │
│  ├── Optimized Kernel Parameters                          │
│  └── Enhanced Security Settings                           │
└─────────────────────────────────────────────────────────────┘
```

## 📦 Component Matrix

### Core Infrastructure

| Component | Script | Status | Description |
|-----------|--------|--------|-------------|
| **RKE2 Kubernetes** | `core.sh` | ✅ Production Ready | Lightweight K8s with enhanced security |
| **Cilium CNI** | `core.sh` | ✅ Auto-Conflict Resolution | eBPF-based networking with conflict detection |
| **Helm** | `core.sh` | ✅ Latest Version | Package manager with repository management |
| **MetalLB** | `core.sh` | ✅ Configured | Load balancer for bare metal deployments |
| **cert-manager** | `core.sh` | ✅ Let's Encrypt Ready | Automated certificate management |

### Database Solutions

| Database | Deployment Method | Features | Status |
|----------|------------------|----------|--------|
| **Percona MongoDB** | Operator-based | Sharding, PMM monitoring, automated backups | ✅ Production Ready |
| **PostgreSQL** | Helm chart | High availability, persistent storage | ✅ Stable |
| **MySQL** | Helm chart | Replication, backup support | ✅ Stable |
| **Redis** | Helm chart | Clustering, persistence | ✅ Stable |
| **MariaDB** | Helm chart | Galera clustering | ✅ Stable |

### CI/CD & GitOps

| Component | Purpose | Access | Status |
|-----------|---------|--------|--------|
| **ArgoCD** | GitOps continuous deployment | Web UI + CLI | ✅ Production Ready |
| **ArgoCD CLI** | Command-line management | `argocd` command | ✅ Installed |
| **Projects** | Multi-environment management | Development/Production projects | ✅ Configured |
| **Applications** | Sample deployments | MongoDB, Monitoring apps | ✅ Templates Ready |

## 🛠️ Script Reference

### Main Scripts

| Script | Purpose | Key Functions |
|--------|---------|---------------|
| `main.sh` | Central orchestrator | Menu-driven deployment, status checks |
| `core.sh` | Kubernetes infrastructure | RKE2, networking, ingress, storage |
| `databases.sh` | Database deployments | All database types with monitoring |
| `monitoring.sh` | Observability stack | Prometheus, Grafana, Loki, PMM |
| `cicd.sh` | CI/CD pipeline | ArgoCD, projects, applications |
| `percona-mongodb-deploy.sh` | Complete MongoDB stack | Operator, cluster, monitoring, backups |

### Utility Scripts

| Script | Purpose | Key Features |
|--------|---------|--------------|
| `check-dependencies.sh` | System preparation | Package installation, system optimization |
| `troubleshoot.sh` | Diagnostics & repair | Automated conflict resolution, health checks |
| `common.sh` | Shared functions | Logging, error handling, utilities |
| `aws.sh` | Cloud integration | AWS CLI, credentials, S3 setup |

## 🔐 Security & Access

### Default Credentials

| Service | Username | Password | Access Method |
|---------|----------|----------|---------------|
| **ArgoCD** | `admin` | Auto-generated | Check deployment output |
| **MongoDB** | `databaseAdmin` | `databaseAdmin123456` | Port-forward 27017 |
| **PMM Server** | `admin` | `admin-password` | Port-forward 8080 |
| **Grafana** | `admin` | `prom-operator` | Port-forward 3000 |

> ⚠️ **Security Notice**: Change all default passwords in production environments!

## 🚨 Troubleshooting

### Automated Diagnostics

```bash
# Run comprehensive diagnostics
sudo ./troubleshoot.sh

# Quick health check
sudo ./troubleshoot.sh
# Select "System Health Check"

# Fix common conflicts
sudo ./troubleshoot.sh
# Select "Fix Cilium Conflicts"
```

## 🤝 Contributing

We welcome contributions from the community! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Quick Start for Contributors

```bash
# Fork the repository
git clone https://github.com/your-username/wity-cloud-cli.git
cd wity-cloud-cli

# Create feature branch
git checkout -b feature/your-feature

# Make your changes and test
sudo ./test/run-tests.sh

# Submit pull request
```

## 📚 Documentation

Comprehensive documentation is available in the `docs/` folder:

- **[Architecture Guide](docs/README.md)** - Detailed system architecture
- **[Percona MongoDB Guide](docs/PERCONA_MONGODB_README.md)** - Database deployment guide
- **[kubectl-ai Integration](docs/kubectl.ai.md)** - AI-powered Kubernetes management
- **[Troubleshooting Guide](docs/IMPROVEMENTS.md)** - Common issues and solutions

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

### Getting Help

1. **Documentation**: Check the `docs/` folder
2. **Issues**: Open an issue on GitHub
3. **Discussions**: Join our community discussions
4. **Automated Diagnostics**: Run `sudo ./troubleshoot.sh`

### Reporting Issues

When reporting issues, please include:

- Output from `sudo ./troubleshoot.sh` (option 5: Collect System Information)
- System specifications (OS, RAM, disk space)
- Deployment steps taken
- Error messages and logs

## 🌟 Community

- **GitHub**: [https://github.com/wityliti/wity-cloud-cli](https://github.com/wityliti/wity-cloud-cli)
- **Website**: [https://wityliti.io](https://wityliti.io)
- **Documentation**: [https://docs.wityliti.io](https://docs.wityliti.io)

## 🎯 Project Status

**Current Version**: 2.0.0
**Status**: Production Ready
**Last Updated**: May 2025

### Recent Achievements

- ✅ Resolved ArgoCD ingress conflicts
- ✅ Implemented intelligent Cilium conflict resolution
- ✅ Added comprehensive troubleshooting automation
- ✅ Enhanced MongoDB operator integration
- ✅ Improved documentation and user experience
- ✅ Added batch mode for automated deployments

### Roadmap

- 🔄 Enhanced security hardening
- 🔄 Multi-cluster management
- 🔄 Advanced backup strategies
- 🔄 Performance optimization tools
- 🔄 Extended cloud provider support

---

**Built with ❤️ by [wityliti.io](https://wityliti.io) for the Kubernetes community**

*Wity Cloud CLI - Making enterprise Kubernetes accessible to everyone* 