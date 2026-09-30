# Google Cloud Skills Boost / Qwiklabs Solutions

Collection of automated scripts and configurations for Google Cloud training labs.

---

## 📑 Labs Included

1. [Automating the Deployment of Infrastructure Using Terraform (CBL036)](#1-automating-the-deployment-of-infrastructure-using-terraform-cbl036)
2. [Configure an Internal Network Load Balancer (GSP041)](#2-configure-an-internal-network-load-balancer-gsp041)

---

## 1. Automating the Deployment of Infrastructure Using Terraform (CBL036)

This lab creates an auto mode VPC network (`mynetwork`), a firewall rule (`mynetwork-allow-http-ssh-rdp-icmp`), and two compute instances (`mynet-vm-1` in `europe-west4-a` and `mynet-vm-2` in `us-east1-d`) using reusable Terraform modules.

### ⚡ Quick Start (Cloud Shell)

Run this single command in **Google Cloud Shell**:

```bash
export ZONE_1=europe-west4-a
export ZONE_2=us-east1-d

curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab_terraform.sh

sudo chmod +x quicklab_terraform.sh

./quicklab_terraform.sh
```

### 📁 Terraform Configuration Files

All Terraform configuration files are located in the [`tfinfra/`](tfinfra/) directory:
- [`tfinfra/provider.tf`](tfinfra/provider.tf): Google provider initialization
- [`tfinfra/mynetwork.tf`](tfinfra/mynetwork.tf): VPC network, firewall rule, and module instantiation
- [`tfinfra/instance/main.tf`](tfinfra/instance/main.tf): VM instance module definition
- [`tfinfra/instance/variables.tf`](tfinfra/instance/variables.tf): Module input variables

---

## 2. Configure an Internal Network Load Balancer (GSP041)

This lab configures an Internal Passthrough Network Load Balancer with managed instance groups, Cloud Router & NAT, regional health checks, and frontend forwarding rules.

### ⚡ Quick Start (Cloud Shell)

Run this command in **Google Cloud Shell**:

```bash
export REGION=asia-southeast1
export ZONE=asia-southeast1-c

curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab.sh

sudo chmod +x quicklab.sh

./quicklab.sh
```

### 🛠️ Quick Fix for Backend Service
```bash
curl -LO raw.githubusercontent.com/Meet8376/test1/main/fix_backend_service.sh && bash fix_backend_service.sh
```

---

## 📁 Repository Structure

```
├── quicklab_terraform.sh     # Automation for Terraform lab (CBL036)
├── tfinfra/                  # Terraform configurations
│   ├── provider.tf
│   ├── mynetwork.tf
│   └── instance/
│       ├── main.tf
│       └── variables.tf
├── quicklab.sh               # Automation for Internal NLB lab (GSP041)
├── setup_internal_lb.sh      # Full setup script for Internal NLB
├── fix_backend_service.sh    # Task 4 backend service fix script
├── commands.sh               # CLI reference commands
├── verify.sh                 # Verification test script
└── README.md                 # Complete documentation
```
