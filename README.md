# Configure an Internal Network Load Balancer (GSP041)

Automated scripts and step-by-step CLI commands for completing the Google Cloud Skills Boost / Qwiklabs lab: **Configure an Internal Network Load Balancer**.

---

## 🏗️ Architecture Overview

Internal Network Load Balancing enables you to scale TCP/UDP services behind a private, internal IP address accessible only to instances within your VPC.

```
                    +---------------------------+
                    |        my-internal-app    |
                    |             VPC           |
                    +-------------+-------------+
                                  |
            +---------------------+---------------------+
            |                                           |
    +-------v--------+                          +-------v--------+
    |    subnet-a    |                          |    subnet-b    |
    | (10.10.20.0/24)|                          | (10.10.30.0/24)|
    +-------+--------+                          +-------+--------+
            |                                           |
    +-------+-------+                                   |
    |  utility-vm   |                                   |
    | (10.10.20.50) |                                   |
    +---------------+                                   |
            |                                           |
            | Traffic to 10.10.30.5 (Port 80)           |
            +-------------------+                       |
                                |                       |
                                v                       v
                      +-------------------+   +--------------------+
                      |   Internal NLB    |   |     my-ilb-ip      |
                      |    (Forwarding)   |-->|   (10.10.30.5)     |
                      +---------+---------+   +--------------------+
                                |
                   +------------+------------+
                   |                         |
                   v                         v
          +-----------------+       +-----------------+
          | instance-group-1|       | instance-group-2|
          |  (asia-east1-c) |       |  (asia-east1-a) |
          |   10.10.20.2    |       |   10.10.30.2    |
          +-----------------+       +-----------------+
                   ^                         ^
                   |                         |
          +--------+-------------------------+--------+
          |         Cloud NAT & Cloud Router          |
          |       nat-config / nat-router-asia-east1  |
          +-------------------------------------------+
```

---

## ⚡ Quick Start (Full Lab Automation)

Run this directly inside **Google Cloud Shell**:

```bash
export REGION=asia-east1
export ZONE=asia-east1-b

curl -LO raw.githubusercontent.com/Meet8376/test1/main/quicklab.sh
sudo chmod +x quicklab.sh
./quicklab.sh
```

---

## 🛠️ Quick Fix for Task 4 ("Please create the backend service with required configuration")

If you configured the load balancer manually or via console and the Task 4 check reports:
> *"Please create the backend service with required configuration."*

Run this quick fix script in Cloud Shell:

```bash
curl -LO raw.githubusercontent.com/Meet8376/test1/main/fix_backend_service.sh
sudo chmod +x fix_backend_service.sh
./fix_backend_service.sh
```

---

## 📋 Step-by-Step CLI Walkthrough

If you prefer to run each step manually, follow the commands below in Google Cloud Shell.

### 0. Environment Setup & Variables

```bash
export REGION="asia-east1"
export ZONE_UTILITY="asia-east1-b"
export ZONE_IG1="asia-east1-c"
export ZONE_IG2="asia-east1-a"
export NETWORK="my-internal-app"
export SUBNET_A="subnet-a"
export SUBNET_B="subnet-b"

gcloud config set compute/region "$REGION"
```

---

### Task 1. Configure Internal Traffic and Health Check Firewall Rules

#### 1.1 Allow internal traffic from subnet range (10.10.0.0/16)
```bash
gcloud compute firewall-rules create fw-allow-lb-access \
    --network=$NETWORK \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=10.10.0.0/16 \
    --target-tags=backend-service \
    --rules=all
```

#### 1.2 Allow Google Cloud health check probes (130.211.0.0/22 & 35.191.0.0/16)
```bash
gcloud compute firewall-rules create fw-allow-health-checks \
    --network=$NETWORK \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=backend-service \
    --rules=tcp:80
```

> **Check Progress:** Click **Check my progress** on Task 1 in the lab.

---

### Task 2. Create a NAT Configuration Using Cloud Router

Because the backend instances do not have external IPs, Cloud NAT allows them to download packages and updates.

#### 2.1 Create Cloud Router
```bash
gcloud compute routers create nat-router-$REGION \
    --network=$NETWORK \
    --region=$REGION
```

#### 2.2 Create Cloud NAT Gateway
```bash
gcloud compute routers nats create nat-config \
    --router=nat-router-$REGION \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges
```

> **Check Progress:** Click **Check my progress** on Task 2 in the lab.

---

### Task 3. Configure Instance Templates and Create Instance Groups

#### 3.1 Re-run Startup Scripts on Existing Backend VMs
Run the startup script so the VMs can install Apache & PHP through Cloud NAT:
```bash
VM1=$(gcloud compute instances list --filter="name ~ 'instance-group-1'" --format="value(name)" | head -n1)
VM2=$(gcloud compute instances list --filter="name ~ 'instance-group-2'" --format="value(name)" | head -n1)

gcloud compute ssh "$VM1" --zone="$ZONE_IG1" --tunnel-through-iap --quiet --command="sudo google_metadata_script_runner startup"
gcloud compute ssh "$VM2" --zone="$ZONE_IG2" --tunnel-through-iap --quiet --command="sudo google_metadata_script_runner startup"
```

#### 3.2 Create the Utility VM (`utility-vm`)
```bash
gcloud compute instances create utility-vm \
    --zone=$ZONE_UTILITY \
    --machine-type=e2-medium \
    --network=$NETWORK \
    --subnet=$SUBNET_A \
    --private-network-ip=10.10.20.50 \
    --no-address \
    --image-family=debian-12 \
    --image-project=debian-cloud
```

#### 3.3 Verify Connectivity from `utility-vm`
```bash
gcloud compute ssh utility-vm --zone=$ZONE_UTILITY --tunnel-through-iap --quiet --command="
curl -s 10.10.20.2
curl -s 10.10.30.2
"
```

> **Check Progress:** Click **Check my progress** on Task 3 in the lab.

---

### Task 4. Configure the Internal Network Load Balancer

#### 4.1 Reserve Static Internal IP (`my-ilb-ip`)
```bash
gcloud compute addresses create my-ilb-ip \
    --region=$REGION \
    --subnet=$SUBNET_B \
    --addresses=10.10.30.5
```

#### 4.2 Create Health Checks (Regional & Global)
```bash
gcloud compute health-checks create tcp my-ilb-health-check \
    --region=$REGION \
    --port=80 \
    --check-interval=10s \
    --timeout=5s \
    --unhealthy-threshold=3 \
    --healthy-threshold=2 2>/dev/null || true

gcloud compute health-checks create tcp my-ilb-health-check \
    --port=80 \
    --check-interval=10s \
    --timeout=5s \
    --unhealthy-threshold=3 \
    --healthy-threshold=2 2>/dev/null || true
```

#### 4.3 Create Regional Backend Service (`my-ilb`) and Add Instance Groups
> **Note:** The backend service must be named **`my-ilb`** to match the lab validator requirement.
```bash
# Create backend service
gcloud compute backend-services create my-ilb \
    --load-balancing-scheme=internal \
    --protocol=TCP \
    --region=$REGION \
    --health-checks=my-ilb-health-check \
    --health-checks-region=$REGION 2>/dev/null || \
gcloud compute backend-services create my-ilb \
    --load-balancing-scheme=internal \
    --protocol=TCP \
    --region=$REGION \
    --health-checks=my-ilb-health-check

# Add instance-group-1
gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-1 \
    --instance-group-zone=$ZONE_IG1 \
    --region=$REGION

# Add instance-group-2
gcloud compute backend-services add-backend my-ilb \
    --instance-group=instance-group-2 \
    --instance-group-zone=$ZONE_IG2 \
    --region=$REGION
```

#### 4.4 Create Forwarding Rule (`my-ilb`)
```bash
gcloud compute forwarding-rules delete my-ilb --region=$REGION --quiet 2>/dev/null || true

gcloud compute forwarding-rules create my-ilb \
    --load-balancing-scheme=internal \
    --ports=80 \
    --network=$NETWORK \
    --subnet=$SUBNET_B \
    --region=$REGION \
    --backend-service=my-ilb \
    --backend-service-region=$REGION \
    --address=my-ilb-ip
```

> **Check Progress:** Click **Check my progress** on Task 4 in the lab.

---

### Task 5. Test the Internal Network Load Balancer

Connect to `utility-vm` and test multiple HTTP requests to the Load Balancer IP (`10.10.30.5`):

```bash
gcloud compute ssh utility-vm --zone=$ZONE_UTILITY --tunnel-through-iap --quiet --command="
for i in {1..10}; do
    curl -s 10.10.30.5 | grep -E 'Server Hostname|Server Location'
done
"
```

Expected Output:
You should see responses alternating between `instance-group-1` in `asia-east1-c` and `instance-group-2` in `asia-east1-a`.

---

## 📁 Repository Structure

```
├── quicklab.sh             # Main automated script (runs all tasks 1-5)
├── setup_internal_lb.sh    # Full setup script
├── fix_backend_service.sh  # Standalone fix for Task 4 backend service check
├── commands.sh             # Copy-paste CLI reference commands
├── verify.sh               # Health check and verification script
└── README.md               # Lab guide and architecture documentation
```
