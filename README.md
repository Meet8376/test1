# Google Cloud Skills Boost / Qwiklabs Solutions

Collection of automated scripts and configurations for Google Cloud training labs.

---

## 📑 Labs Included

1. [Configure Cloud SQL (CBL037)](#1-configure-cloud-sql-cbl037)
2. [Configure an Application Load Balancer with Autoscaling (OCBL105)](#2-configure-an-application-load-balancer-with-autoscaling-ocbl105)
3. [Configure an Internal Network Load Balancer (GSP041)](#3-configure-an-internal-network-load-balancer-gsp041)
4. [Automating the Deployment of Infrastructure Using Terraform (CBL036)](#4-automating-the-deployment-of-infrastructure-using-terraform-cbl036)

---

## 1. Configure Cloud SQL (CBL037)

Configures a Cloud SQL MySQL 8.0 Enterprise instance with Private IP peering on the default VPC network, SSD storage, creates the `wordpress` database, launches the Cloud SQL Auth Proxy on `wordpress-proxy`, and connects WordPress frontends over both proxy and internal Private IP.

### ⚡ Quick Start (Cloud Shell)

Run this single command in **Google Cloud Shell**:

```bash
curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab_cloud_sql.sh

sudo chmod +x quicklab_cloud_sql.sh

./quicklab_cloud_sql.sh
```

---

## 2. Configure an Application Load Balancer with Autoscaling (OCBL105)

Deploys a global external Application Load Balancer (HTTP) with backends in two regions (`us-east4` and `asia-east1`), custom web server images, managed instance groups, autoscaling, and autohealing.

### ⚡ Quick Start (Cloud Shell)

```bash
curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab_alb_autoscaling.sh

sudo chmod +x quicklab_alb_autoscaling.sh

./quicklab_alb_autoscaling.sh
```

*(Note: For Task 6 stress test quick fix, run `curl -LO raw.githubusercontent.com/Meet8376/test1/main/fix_task6_stress_test.sh && chmod +x fix_task6_stress_test.sh && ./fix_task6_stress_test.sh`)*

---

## 3. Configure an Internal Network Load Balancer (GSP041)

Configures an Internal Passthrough Network Load Balancer with managed instance groups, Cloud Router & NAT, regional health checks, and frontend forwarding rules.

### ⚡ Quick Start (Cloud Shell)

```bash
export REGION=asia-southeast1
export ZONE=asia-southeast1-c

curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab.sh

sudo chmod +x quicklab.sh

./quicklab.sh
```

---

## 4. Automating the Deployment of Infrastructure Using Terraform (CBL036)

Deploys an auto mode VPC network (`mynetwork`), firewall rule (`mynetwork-allow-http-ssh-rdp-icmp`), and two compute instances (`mynet-vm-1` and `mynet-vm-2`) using reusable Terraform modules.

### ⚡ Quick Start (Cloud Shell)

```bash
export ZONE_1=europe-west4-a
export ZONE_2=us-east1-d

curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab_terraform.sh

sudo chmod +x quicklab_terraform.sh

./quicklab_terraform.sh
```

---

## 📁 Repository Structure

```
├── quicklab_cloud_sql.sh       # Automation for Cloud SQL lab (CBL037)
├── quicklab_alb_autoscaling.sh # Automation for ALB with Autoscaling (OCBL105)
├── fix_task6_stress_test.sh    # Task 6 quick fix for OCBL105
├── quicklab.sh                 # Automation for Internal NLB lab (GSP041)
├── quicklab_terraform.sh       # Automation for Terraform lab (CBL036)
├── tfinfra/                    # Terraform configurations for CBL036
│   ├── provider.tf
│   ├── mynetwork.tf
│   └── instance/
│       ├── main.tf
│       └── variables.tf
└── README.md                   # Full documentation & guides
```
