#!/bin/bash

# Source common functions if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -f "./common.sh" ]]; then
    source "./common.sh"
  else
    echo "common.sh not found. This script requires common functions."
    exit 1
  fi
fi

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

function setup_aws_cli() {
  section "Setting up AWS CLI and credentials"

  # Check and install dependencies
  echo -e "${YELLOW}Checking and installing dependencies...${NC}"
  
  # Update package list
  apt-get update
  
  # Install required packages
  apt-get install -y unzip curl
  
  # Check if AWS CLI is already installed
  if command -v aws &> /dev/null; then
    echo -e "${YELLOW}AWS CLI is already installed. Version:${NC}"
    aws --version
    if ask_approval "Do you want to reinstall AWS CLI?"; then
      echo "Proceeding with reinstallation..."
    else
      echo "Skipping AWS CLI installation."
      return 0
    fi
  fi

  # Install AWS CLI v2
  echo -e "${YELLOW}Downloading and installing AWS CLI v2...${NC}"
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  sudo ./aws/install --update
  rm -rf awscliv2.zip aws

  # Verify installation
  if command -v aws &> /dev/null; then
    echo -e "${GREEN}AWS CLI installed successfully. Version:${NC}"
    aws --version
  else
    echo -e "${RED}AWS CLI installation failed${NC}"
    return 1
  fi

  echo -e "${YELLOW}Enter your AWS credentials to configure CLI access:${NC}"
  read -p "AWS Access Key ID: " aws_access_key_id
  read -s -p "AWS Secret Access Key: " aws_secret_access_key
  echo
  read -p "AWS Region (e.g. us-east-1): " aws_region

  mkdir -p ~/.aws
  cat <<EOF > ~/.aws/credentials
[default]
aws_access_key_id=${aws_access_key_id}
aws_secret_access_key=${aws_secret_access_key}
EOF

  cat <<EOF > ~/.aws/config
[default]
region=${aws_region}
output=json
EOF

  echo -e "${GREEN}AWS CLI is now configured.${NC}"
  echo -e "${YELLOW}You can now access S3, Route 53, and ECR services from this node.${NC}"
  
  # Test AWS CLI configuration
  echo -e "${YELLOW}Testing AWS CLI configuration...${NC}"
  if aws sts get-caller-identity &> /dev/null; then
    echo -e "${GREEN}AWS CLI configuration test successful${NC}"
  else
    echo -e "${RED}AWS CLI configuration test failed. Please check your credentials.${NC}"
  fi
}

function create_s3_bucket_for_velero() {
  section "Creating S3 Bucket for Velero Backups"
  read -p "Enter a unique S3 bucket name for Velero backups: " bucket_name
  aws s3api create-bucket --bucket "$bucket_name" --region $(aws configure get region) --create-bucket-configuration LocationConstraint=$(aws configure get region)
  echo -e "${GREEN}S3 bucket '$bucket_name' created.${NC}"
  echo "$bucket_name" > ~/.velero_bucket
}

function push_sample_image_to_ecr() {
  section "Pushing Sample Image to Amazon ECR"
  read -p "Enter ECR repo name to create (e.g. my-k8s-app): " repo_name
  aws ecr create-repository --repository-name "$repo_name" || true
  aws ecr get-login-password | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com
  docker pull nginx:latest
  docker tag nginx:latest $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com/${repo_name}:latest
  docker push $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com/${repo_name}:latest
  echo -e "${GREEN}Image pushed to ECR: ${repo_name}${NC}"
}

function setup_route53_record() {
  section "Creating Route53 A Record for Traefik/Rancher"
  read -p "Enter your hosted zone domain (e.g. example.com): " zone_name
  read -p "Enter the subdomain (e.g. rancher): " subdomain
  public_ip=$(curl -s http://checkip.amazonaws.com)
  zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "$zone_name." --query "HostedZones[0].Id" --output text)

  cat <<EOF > r53-record.json
{
  "Comment": "Create A record for ${subdomain}.${zone_name}",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${subdomain}.${zone_name}",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{
        "Value": "${public_ip}"
      }]
    }
  }]
}
EOF

  aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch file://r53-record.json
  echo -e "${GREEN}DNS A record created: ${subdomain}.${zone_name} -> ${public_ip}${NC}"
  rm r53-record.json
}

function configure_base_domain() {
  section "Configure base domain and deduce subdomains"
  read -p "Enter base domain (e.g. k8s.mycompany.com): " BASE_FQDN

  BASE_SUBDOMAIN=$(echo "$BASE_FQDN" | cut -d. -f1)
  ROOT_DOMAIN=$(echo "$BASE_FQDN" | cut -d. -f2-)

  # Create associative array for service domains
  # This will be saved to a file that can be sourced by other scripts
  cat <<EOF > ~/.cluster_domains
# Service domains derived from base domain ${BASE_FQDN}
export BASE_FQDN="${BASE_FQDN}"
export ROOT_DOMAIN="${ROOT_DOMAIN}"

declare -A SERVICE_DOMAINS
SERVICE_DOMAINS=(
  [rancher]="rancher.${BASE_FQDN}"
  [grafana]="grafana.${BASE_FQDN}"
  [prometheus]="prometheus.${BASE_FQDN}"
  [pgadmin]="pgadmin.${BASE_FQDN}"
  [minio]="minio.${BASE_FQDN}"
  [loki]="loki.${BASE_FQDN}"
  [argocd]="argocd.${BASE_FQDN}"
  [velero]="velero.${BASE_FQDN}"
  [traefik]="traefik.${BASE_FQDN}"
)
EOF

  # Also create a simplified version
  echo "$BASE_FQDN" > ~/.cluster_fqdn

  source ~/.cluster_domains
  
  echo -e "${GREEN}Subdomains derived for services:${NC}"
  for key in "${!SERVICE_DOMAINS[@]}"; do
    echo "  $key: ${SERVICE_DOMAINS[$key]}"
  done
}

function setup_all_route53_records() {
  section "Creating Route53 A Records for All Components"
  
  # Source domain configuration
  if [[ -f ~/.cluster_domains ]]; then
    source ~/.cluster_domains
  else
    echo -e "${YELLOW}No domain configuration found. Please run 'Configure Domain' first.${NC}"
    return 1
  fi
  
  read -p "Enter your hosted zone domain (e.g. mycompany.com): " zone_name
  zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "$zone_name." --query "HostedZones[0].Id" --output text)
  public_ip=$(curl -s http://checkip.amazonaws.com)

  for key in "${!SERVICE_DOMAINS[@]}"; do
    hostname="${SERVICE_DOMAINS[$key]}"
    cat <<EOF > tmp-${key}.json
{
  "Comment": "Create A record for ${hostname}",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${hostname}",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{
        "Value": "${public_ip}"
      }]
    }
  }]
}
EOF
    aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch file://tmp-${key}.json
    echo -e "${GREEN}Created: ${hostname} -> ${public_ip}${NC}"
    rm tmp-${key}.json
  done
}

# Only run if script is called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Running AWS Integration script directly"
  PS3='Select AWS integration: '
  options=("AWS CLI Setup" "S3 Bucket for Velero" "Push to ECR" "Configure Domain" "Route53 Record" "Setup All Route53 Records" "Quit")
  
  select opt in "${options[@]}"; do
    case $opt in
      "AWS CLI Setup")
        setup_aws_cli
        ;;
      "S3 Bucket for Velero")
        create_s3_bucket_for_velero
        ;;
      "Push to ECR")
        push_sample_image_to_ecr
        ;;
      "Configure Domain")
        configure_base_domain
        ;;
      "Route53 Record")
        setup_route53_record
        ;;
      "Setup All Route53 Records")
        setup_all_route53_records
        ;;
      "Quit")
        break
        ;;
      *) 
        echo "Invalid option $REPLY"
        ;;
    esac
  done
fi 