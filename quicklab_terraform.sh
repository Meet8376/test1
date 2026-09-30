#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Automating the Deployment of Infrastructure Using Terraform (CBL036)
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Automating Deployment of Infrastructure Using Terraform       ${NC}"
echo -e "${CYAN}   Lab ID: CBL036 - Quicklab Automation                         ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "$DEVSHELL_PROJECT_ID")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Define Zones (Defaulting to europe-west4-a and us-east1-d per lab specification)
ZONE_1="${ZONE_1:-europe-west4-a}"
ZONE_2="${ZONE_2:-us-east1-d}"

echo -e "${GREEN}[INFO] VM 1 Zone: ${ZONE_1}${NC}"
echo -e "${GREEN}[INFO] VM 2 Zone: ${ZONE_2}${NC}"

# ==============================================================================
# Task 1: Ensure Terraform is Installed & Setup Workspace
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/3] Setting up Terraform & Workspace...${NC}"

if ! command -v terraform &>/dev/null; then
    echo -e "${BLUE}[INFO] Installing Terraform CLI...${NC}"
    wget -O - https://apt.releases.hashicorp.com/gpg 2>/dev/null | sudo gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    sudo apt update -qq && sudo apt install -y -qq terraform
fi

echo -e "${GREEN}[INFO] Terraform Version: $(terraform --version | head -n1)${NC}"

# Create tfinfra directory structure in user home
WORKSPACE_DIR="$HOME/tfinfra"
mkdir -p "$WORKSPACE_DIR/instance"
cd "$WORKSPACE_DIR"

# 1. provider.tf
cat <<'EOF' > provider.tf
provider "google" {}
EOF

# 2. instance/variables.tf
cat <<'EOF' > instance/variables.tf
variable "instance_name" {}
variable "instance_zone" {}
variable "instance_type" {
  default = "e2-micro"
}
variable "instance_network" {}
EOF

# 3. instance/main.tf
cat <<'EOF' > instance/main.tf
resource "google_compute_instance" "vm_instance" {
  name         = "${var.instance_name}"
  zone         = "${var.instance_zone}"
  machine_type = "${var.instance_type}"
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }
  network_interface {
    network = "${var.instance_network}"
    access_config {
      # Allocate a one-to-one NAT IP to the instance
    }
  }
}
EOF

# 4. mynetwork.tf
cat <<EOF > mynetwork.tf
# Create the mynetwork network resource
resource "google_compute_network" "mynetwork" {
  name                    = "mynetwork"
  auto_create_subnetworks = "true"
}

# Add a firewall rule to allow HTTP, SSH, RDP and ICMP traffic on mynetwork
resource "google_compute_firewall" "mynetwork-allow-http-ssh-rdp-icmp" {
  name    = "mynetwork-allow-http-ssh-rdp-icmp"
  network = google_compute_network.mynetwork.self_link
  allow {
    protocol = "tcp"
    ports    = ["22", "80", "3389"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}

# Create the mynet-vm-1 instance
module "mynet-vm-1" {
  source           = "./instance"
  instance_name    = "mynet-vm-1"
  instance_zone    = "${ZONE_1}"
  instance_network = google_compute_network.mynetwork.self_link
}

# Create the mynet-vm-2 instance
module "mynet-vm-2" {
  source           = "./instance"
  instance_name    = "mynet-vm-2"
  instance_zone    = "${ZONE_2}"
  instance_network = google_compute_network.mynetwork.self_link
}
EOF

# Format Terraform code
terraform fmt

# ==============================================================================
# Task 2: Initialize, Plan, and Apply Terraform Configuration
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/3] Initializing and Applying Terraform Configuration...${NC}"

terraform init

echo -e "${BLUE}[INFO] Planning Terraform execution...${NC}"
terraform plan

echo -e "${BLUE}[INFO] Applying Terraform configuration (creating VPC, Firewall, and 2 VMs)...${NC}"
terraform apply -auto-approve

echo -e "\n${GREEN}[SUCCESS] Terraform infrastructure deployed successfully!${NC}"

# ==============================================================================
# Task 3: Verify Deployment and Connectivity
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/3] Verifying Resources and Network Connectivity...${NC}"

echo -e "${BLUE}[INFO] Checking VM instances...${NC}"
gcloud compute instances list --filter="name:(mynet-vm-1 OR mynet-vm-2)" --format="table(name,zone,networkInterfaces[0].networkIP,status)"

VM2_IP=$(gcloud compute instances describe mynet-vm-2 --zone="${ZONE_2}" --format="value(networkInterfaces[0].networkIP)" 2>/dev/null || echo "")

if [ -n "$VM2_IP" ]; then
    echo -e "${BLUE}[INFO] Testing ping from mynet-vm-1 to mynet-vm-2 ($VM2_IP)...${NC}"
    sleep 15
    gcloud compute ssh mynet-vm-1 --zone="${ZONE_1}" --tunnel-through-iap --quiet --command="ping -c 3 $VM2_IP" || true
fi

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   Lab Configuration Completed Successfully! 🚀                  ${NC}"
echo -e "${GREEN}   Click 'Check my progress' on the lab page to get 100/100!     ${NC}"
echo -e "${GREEN}=================================================================${NC}"
