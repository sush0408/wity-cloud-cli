#!/bin/bash

# Dependency Check and Installation Script
# Ensures all required tools are available for Wity Cloud Deploy

# Source common functions
if [[ -f "./common.sh" ]]; then
  source "./common.sh"
else
  echo "common.sh not found. This script requires common functions."
  exit 1
fi

# Function to check if running as root
check_root_access() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root or with sudo${NC}"
    echo "Please run: sudo $0"
    exit 1
  fi
}

# Function to check system requirements
check_system_requirements() {
  section "Checking system requirements"
  
  # Check OS
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    echo -e "${GREEN}Operating System: $PRETTY_NAME${NC}"
    
    # Check if it's a supported OS
    case $ID in
      ubuntu|debian)
        echo -e "${GREEN}Supported OS detected${NC}"
        ;;
      centos|rhel|fedora)
        echo -e "${YELLOW}RHEL-based OS detected. Some commands may need adjustment.${NC}"
        ;;
      *)
        echo -e "${YELLOW}Unsupported OS detected. Proceed with caution.${NC}"
        ;;
    esac
  else
    echo -e "${YELLOW}Cannot determine OS version${NC}"
  fi
  
  # Check architecture
  ARCH=$(uname -m)
  echo -e "${GREEN}Architecture: $ARCH${NC}"
  
  if [[ "$ARCH" != "x86_64" ]]; then
    echo -e "${YELLOW}Warning: Non-x86_64 architecture detected. Some tools may not be available.${NC}"
  fi
  
  # Check available memory
  MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
  echo -e "${GREEN}Available Memory: ${MEMORY_GB}GB${NC}"
  
  if [[ $MEMORY_GB -lt 4 ]]; then
    echo -e "${YELLOW}Warning: Less than 4GB RAM available. MongoDB deployment may be resource-constrained.${NC}"
  fi
  
  # Check available disk space
  DISK_SPACE=$(df -h / | awk 'NR==2{print $4}')
  echo -e "${GREEN}Available Disk Space: $DISK_SPACE${NC}"
}

# Function to install essential packages
install_essential_packages() {
  section "Installing essential packages"
  
  echo -e "${YELLOW}Updating package lists...${NC}"
  apt-get update
  
  echo -e "${YELLOW}Installing essential packages...${NC}"
  apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    jq \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    vim \
    nano \
    htop \
    net-tools \
    dnsutils \
    tree \
    rsync \
    tar \
    gzip \
    openssl \
    python3 \
    python3-pip
  
  echo -e "${GREEN}Essential packages installed successfully${NC}"
}

# Function to install Docker if not present
install_docker() {
  section "Checking Docker installation"
  
  if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker is already installed${NC}"
    docker --version
    return 0
  fi
  
  echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
  
  # Add Docker's official GPG key
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  
  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Install Docker
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  
  # Start and enable Docker
  systemctl start docker
  systemctl enable docker
  
  # Add current user to docker group (if not root)
  if [[ $SUDO_USER ]]; then
    usermod -aG docker $SUDO_USER
    echo -e "${YELLOW}Added $SUDO_USER to docker group. Please log out and back in for changes to take effect.${NC}"
  fi
  
  echo -e "${GREEN}Docker installed successfully${NC}"
  docker --version
}

# Function to install Helm
install_helm() {
  section "Checking Helm installation"
  
  if command -v helm &> /dev/null; then
    echo -e "${GREEN}Helm is already installed${NC}"
    helm version
    return 0
  fi
  
  echo -e "${YELLOW}Helm not found. Installing Helm...${NC}"
  
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
  apt-get update
  apt-get install -y helm
  
  echo -e "${GREEN}Helm installed successfully${NC}"
  helm version
}

# Function to check kubectl availability
check_kubectl() {
  section "Checking kubectl availability"
  
  if command -v kubectl &> /dev/null; then
    echo -e "${GREEN}kubectl is available${NC}"
    kubectl version --client
    
    # Check if kubectl can connect to cluster
    if kubectl cluster-info &> /dev/null; then
      echo -e "${GREEN}kubectl can connect to Kubernetes cluster${NC}"
    else
      echo -e "${YELLOW}kubectl found but cannot connect to cluster${NC}"
      echo -e "${YELLOW}This is normal if Kubernetes is not yet installed${NC}"
    fi
  else
    echo -e "${YELLOW}kubectl not found${NC}"
    echo -e "${YELLOW}kubectl will be installed with RKE2 during core setup${NC}"
  fi
}

# Function to verify all dependencies
verify_dependencies() {
  section "Verifying all dependencies"
  
  local required_tools=("curl" "wget" "unzip" "git" "jq" "docker")
  local missing_tools=()
  
  for tool in "${required_tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
      echo -e "${GREEN}✓ $tool is available${NC}"
    else
      echo -e "${RED}✗ $tool is missing${NC}"
      missing_tools+=("$tool")
    fi
  done
  
  if [[ ${#missing_tools[@]} -eq 0 ]]; then
    echo -e "${GREEN}All required dependencies are available${NC}"
    return 0
  else
    echo -e "${RED}Missing dependencies: ${missing_tools[*]}${NC}"
    return 1
  fi
}

# Function to create system optimization
optimize_system() {
  section "Applying system optimizations"
  
  # Increase file limits
  cat > /etc/security/limits.d/99-kubernetes.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF

  # Optimize kernel parameters
  cat > /etc/sysctl.d/99-kubernetes.conf << EOF
# Kubernetes optimizations
vm.swappiness=1
fs.inotify.max_user_watches=524288
fs.file-max=131072
vm.max_map_count=262144
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.conf.all.forwarding=1

# MongoDB optimizations
vm.dirty_ratio=15
vm.dirty_background_ratio=5
EOF

  sysctl --system
  
  echo -e "${GREEN}System optimizations applied${NC}"
}

# Main function
main() {
  echo -e "${GREEN}Wity Cloud Deploy - Dependency Check and Installation${NC}"
  echo "=================================================="
  
  check_root_access
  check_system_requirements
  
  if ask_approval "Do you want to install essential packages?"; then
    install_essential_packages
  fi
  
  if ask_approval "Do you want to install Docker?"; then
    install_docker
  fi
  
  if ask_approval "Do you want to install Helm?"; then
    install_helm
  fi
  
  check_kubectl
  
  if ask_approval "Do you want to apply system optimizations?"; then
    optimize_system
  fi
  
  echo ""
  verify_dependencies
  
  echo ""
  echo -e "${GREEN}Dependency check completed!${NC}"
  echo "=================================================="
  echo "Next steps:"
  echo "1. Run './core.sh' to install RKE2 Kubernetes"
  echo "2. Run './percona-mongodb-deploy.sh' for complete MongoDB stack"
  echo "3. Run './monitoring.sh' for monitoring components"
  echo "4. Run './aws.sh' for AWS integration"
}

# Function to ask for approval (if not already defined)
if ! declare -f ask_approval > /dev/null; then
  ask_approval() {
    local message=$1
    if [[ "${BATCH_MODE:-false}" == "true" ]]; then
      echo -e "${BLUE}$message${NC} - Auto-approved (batch mode)"
      return 0
    fi
    echo -e "${BLUE}$message${NC} (y/n)"
    read -r approval
    if [[ ! $approval =~ ^[Yy]$ ]]; then
      echo "Skipping this step..."
      return 1
    fi
    return 0
  }
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi 