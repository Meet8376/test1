# Google Cloud Skills Boost / Qwiklabs Solutions

Collection of automated scripts and configurations for Google Cloud training labs.

---

## 📑 Labs Included

1. [Configure Cloud SQL (CBL037)](#1-configure-cloud-sql-cbl037)
2. [Configure an Application Load Balancer with Autoscaling (OCBL105)](#2-configure-an-application-load-balancer-with-autoscaling-ocbl105)
3. [Configure an Internal Network Load Balancer (GSP041)](#3-configure-an-internal-network-load-balancer-gsp041)
4. [Automating the Deployment of Infrastructure Using Terraform (CBL036)](#4-automating-the-deployment-of-infrastructure-using-terraform-cbl036)
5. [Accessing the Google Cloud Console and Cloud Shell (CBL138)](#5-accessing-the-google-cloud-console-and-cloud-shell-cbl138)
6. [Working with Cloud Build (CBL139)](#6-working-with-cloud-build-cbl139)
7. [Deploying GKE Autopilot Clusters](#7-deploying-gke-autopilot-clusters)
8. [Deploying GKE Autopilot Clusters from Cloud Shell](#8-deploying-gke-autopilot-clusters-from-cloud-shell)
9. [Implementing Least Privilege IAM Policy Bindings in Cloud Run (CBL418)](#9-implementing-least-privilege-iam-policy-bindings-in-cloud-run-cbl418)
10. [Using Cloud Pub/Sub with Cloud Run (CBL396)](#10-using-cloud-pubsub-with-cloud-run-cbl396)
11. [Develop and Deploy Cloud Run Functions (CBL491)](#11-develop-and-deploy-cloud-run-functions-cbl491)
12. [Connect Cloud Run Functions (CBL492)](#12-connect-cloud-run-functions-cbl492)

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

## 5. Accessing the Google Cloud Console and Cloud Shell (CBL138)

Configures Compute Engine VM (`first-vm`) with HTTP firewall rules and an IAM Service Account (`test-service-account`), creates multi-region Cloud Storage buckets with uniform access and public read permissions, clones repository and customizes welcome page with Nginx on the VM.

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_console_cloudshell.sh?cache=$(date +%s)" -o quicklab_console_cloudshell.sh

chmod +x quicklab_console_cloudshell.sh

./quicklab_console_cloudshell.sh
```

---

## 6. Working with Cloud Build (CBL139)

Builds container images using a Dockerfile, pushes them to Artifact Registry, creates custom YAML-formatted Cloud Build configurations (`cloudbuild.yaml`), and implements automated container testing and failure handling (`cloudbuild2.yaml`).

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_cloud_build.sh?cache=$(date +%s)" -o quicklab_cloud_build.sh

chmod +x quicklab_cloud_build.sh

./quicklab_cloud_build.sh
```

---

## 7. Deploying GKE Autopilot Clusters

Provisions a fully-managed GKE Autopilot cluster (`autopilot-cluster-1`) in `us-east1` and deploys a sample 3-replica Nginx workload (`nginx-1`).

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_gke_autopilot.sh?cache=$(date +%s)" -o quicklab_gke_autopilot.sh

chmod +x quicklab_gke_autopilot.sh

./quicklab_gke_autopilot.sh
```

---

## 8. Deploying GKE Autopilot Clusters from Cloud Shell

Provisions a GKE Autopilot cluster (`autopilot-cluster-1`) in `europe-west1` via Cloud Shell CLI, deploys and customizes an Nginx workload exposed via LoadBalancer, and deploys a secondary Pod using a YAML manifest (`new-nginx-pod.yaml`).

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_gke_cloudshell.sh?cache=$(date +%s)" -o quicklab_gke_cloudshell.sh

chmod +x quicklab_gke_cloudshell.sh

./quicklab_gke_cloudshell.sh
```

---

## 9. Implementing Least Privilege IAM Policy Bindings in Cloud Run (CBL418)

Deploys Cloud Run services, secures endpoints by enforcing authentication, creates dedicated service accounts (`Billing Initiator`), tests token-based authenticated invocations, and enforces least-privilege IAM bindings directly on target services.

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_least_privilege_cloud_run.sh?cache=$(date +%s)" -o quicklab_least_privilege_cloud_run.sh

chmod +x quicklab_least_privilege_cloud_run.sh

./quicklab_least_privilege_cloud_run.sh
```

---

## 10. Using Cloud Pub/Sub with Cloud Run (CBL396)

Integrates Cloud Run microservices with Google Cloud Pub/Sub: deploys a public producer (`store-service`) and a private consumer (`order-service`), creates the `ORDER_PLACED` topic, provisions an authorized invoker service account (`pubsub-cloud-run-invoker`), configures push subscriptions, and tests end-to-end event-driven message delivery.

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_pubsub_cloud_run.sh?cache=$(date +%s)" -o quicklab_pubsub_cloud_run.sh

chmod +x quicklab_pubsub_cloud_run.sh

./quicklab_pubsub_cloud_run.sh
```

---

## 11. Develop and Deploy Cloud Run Functions (CBL491)

Deploys 2nd Generation Cloud Run functions: an authenticated HTTP function (`temperature-converter`), an event-driven Cloud Storage trigger (`temperature-data-checker`), and creates service revisions with environment variable configurations (`TEMP_CONVERT_TO=ctof`).

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_cloud_run_functions.sh?cache=$(date +%s)" -o quicklab_cloud_run_functions.sh

chmod +x quicklab_cloud_run_functions.sh

./quicklab_cloud_run_functions.sh
```

---

## 12. Connect Cloud Run Functions (CBL492)

Provisions Memorystore for Redis (`customerdb`), configures Serverless VPC Access (`test-connector`), connects event-driven Pub/Sub and HTTP Cloud Run functions to the internal Redis instance, and connects to an internal Compute Engine web server VM using VPC egress.

### ⚡ Quick Start (Cloud Shell)

```bash
curl -sL "https://raw.githubusercontent.com/Meet8376/test1/main/quicklab_connect_cloud_run_functions.sh?cache=$(date +%s)" -o quicklab_connect_cloud_run_functions.sh

chmod +x quicklab_connect_cloud_run_functions.sh

./quicklab_connect_cloud_run_functions.sh
```

---

## 📁 Repository Structure

```
├── quicklab_connect_cloud_run_functions.sh # Automation for Connect Cloud Run Functions (CBL492)
├── quicklab_cloud_run_functions.sh         # Automation for Cloud Run Functions lab (CBL491)
├── quicklab_pubsub_cloud_run.sh            # Automation for Pub/Sub with Cloud Run lab (CBL396)
├── quicklab_least_privilege_cloud_run.sh   # Automation for Least Privilege Cloud Run lab (CBL418)
├── quicklab_gke_cloudshell.sh              # Automation for GKE from Cloud Shell lab
├── quicklab_gke_autopilot.sh               # Automation for GKE Autopilot lab
├── quicklab_cloud_build.sh                 # Automation for Cloud Build lab (CBL139)
├── quicklab_console_cloudshell.sh          # Automation for Console & Cloud Shell lab (CBL138)
├── fix_first_vm.sh                         # Task 1 & 3 quick fix for CBL138
├── quicklab_cloud_sql.sh                   # Automation for Cloud SQL lab (CBL037)
├── fix_task2_proxy.sh                      # Task 2 quick fix for CBL037
├── quicklab_alb_autoscaling.sh             # Automation for ALB with Autoscaling (OCBL105)
├── fix_task6_stress_test.sh                # Task 6 quick fix for OCBL105
├── quicklab.sh                             # Automation for Internal NLB lab (GSP041)
├── quicklab_terraform.sh                   # Automation for Terraform lab (CBL036)
├── tfinfra/                                # Terraform configurations for CBL036
│   ├── provider.tf
│   ├── mynetwork.tf
│   └── instance/
│       ├── main.tf
│       └── variables.tf
└── README.md                               # Full documentation & guides
```
