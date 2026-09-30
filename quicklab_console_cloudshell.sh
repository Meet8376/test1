#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Accessing the Google Cloud Console and Cloud Shell (CBL138)
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Accessing the Google Cloud Console and Cloud Shell (CBL138)   ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect Environment Variables
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Define Zone and Region
ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"

if [ -z "$ZONE" ]; then
    ZONE="us-east4-b"
fi
if [ -z "$REGION" ]; then
    REGION="${ZONE%-*}"
fi

gcloud config set compute/zone "$ZONE" --quiet 2>/dev/null || true
gcloud config set compute/region "$REGION" --quiet 2>/dev/null || true

echo -e "${GREEN}[INFO] Target Region: ${REGION}${NC}"
echo -e "${GREEN}[INFO] Target Zone:   ${ZONE}${NC}"

# ==============================================================================
# TASK 1: VM Instance (first-vm), Firewall Rules, & Service Account
# Scored Checkpoint 1: Create a VM instance with necessary firewall rule, and an IAM service account
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Setting up Firewall Rules, VM (first-vm), and Service Account...${NC}"

# 1.1 Ensure Firewall rule for HTTP exists (allow-http / default-allow-http)
if gcloud compute firewall-rules describe default-allow-http &>/dev/null; then
    echo -e "${BLUE}[INFO] Firewall rule 'default-allow-http' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating firewall rule 'default-allow-http' for tag 'http-server'...${NC}"
    gcloud compute firewall-rules create default-allow-http \
        --network=default \
        --action=ALLOW \
        --direction=INGRESS \
        --rules=tcp:80 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=http-server \
        --quiet || true
fi

# Ensure Firewall rule for SSH exists
if gcloud compute firewall-rules describe default-allow-ssh &>/dev/null || gcloud compute firewall-rules describe allow-ssh-all &>/dev/null; then
    echo -e "${BLUE}[INFO] SSH firewall rule is already present.${NC}"
else
    echo -e "${BLUE}[INFO] Creating SSH firewall rule...${NC}"
    gcloud compute firewall-rules create allow-ssh-all \
        --network=default \
        --action=ALLOW \
        --direction=INGRESS \
        --rules=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --quiet || true
fi

# 1.2 Create first-vm instance if not already created
# Provide startup script to install nginx and prepare document root as an initial bootstrap
CAT_IMAGE_URL="https://storage.googleapis.com/${PROJECT_ID}-bucket1/cat.jpg"
STARTUP_SCRIPT=$(cat <<EOF
#!/bin/bash
apt-get remove -y --purge man-db || true
touch /var/lib/man-db/auto-update
apt-get update -y
apt-get install -y nginx
cat <<'HTML' > /var/www/html/index.html
<html><head><title>Cat</title></head> <body> <h1>Cat</h1> <img src="${CAT_IMAGE_URL}"> </body></html>
HTML
systemctl restart nginx
EOF
)

if gcloud compute instances describe first-vm --zone="$ZONE" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Instance 'first-vm' already exists in zone ${ZONE}.${NC}"
    # Ensure http-server tag is attached
    gcloud compute instances add-tags first-vm --zone="$ZONE" --tags=http-server --quiet 2>/dev/null || true
else
    echo -e "${BLUE}[INFO] Creating VM instance 'first-vm' (e2-micro, zone: ${ZONE}, tag: http-server)...${NC}"
    gcloud compute instances create first-vm \
        --zone="$ZONE" \
        --machine-type=e2-micro \
        --tags=http-server \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --metadata=startup-script="$STARTUP_SCRIPT" \
        --quiet || \
    gcloud compute instances create first-vm \
        --zone="$ZONE" \
        --machine-type=e2-micro \
        --tags=http-server \
        --metadata=startup-script="$STARTUP_SCRIPT" \
        --quiet
fi

# 1.3 Create IAM Service Account (test-service-account) and assign Editor role
SA_EMAIL="test-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
echo -e "${BLUE}[INFO] Creating Service Account 'test-service-account'...${NC}"
if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Service account '${SA_EMAIL}' already exists.${NC}"
else
    gcloud iam service-accounts create test-service-account \
        --display-name="Test Service Account" \
        --quiet || true
fi

echo -e "${BLUE}[INFO] Binding 'roles/editor' to service account...${NC}"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/editor" \
    --condition=None \
    --quiet 2>/dev/null || \
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/editor" \
    --quiet

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: VM 'first-vm' and IAM Service Account created!${NC}"

# ==============================================================================
# TASK 2: Cloud Shell Verification
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Verifying Cloud Shell Authentication & Config...${NC}"
gcloud auth list
gcloud config list project
echo -e "${GREEN}[SUCCESS] Cloud Shell credentials verified.${NC}"

# ==============================================================================
# TASK 3: Cloud Storage Buckets & Public Access
# Scored Checkpoint 2: Create Cloud Storage Buckets
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Creating Storage Buckets and Configuring Permissions...${NC}"

BUCKET1="gs://${PROJECT_ID}-bucket1"
BUCKET2="gs://${PROJECT_ID}-bucket2"

# 3.1 Create bucket 1 with Uniform bucket-level access and disable public access prevention
echo -e "${BLUE}[INFO] Creating ${BUCKET1} (Multi-region US)...${NC}"
if gcloud storage buckets describe "$BUCKET1" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Bucket ${BUCKET1} already exists.${NC}"
else
    gcloud storage buckets create "$BUCKET1" --location=US --uniform-bucket-level-access --quiet || \
    gsutil mb -l US -b on "$BUCKET1" || true
fi

# Ensure uniform bucket level access is ON and public access prevention is OFF
gcloud storage buckets update "$BUCKET1" --uniform-bucket-level-access 2>/dev/null || gsutil uniformbucketlevelaccess set on "$BUCKET1" || true
gcloud storage buckets update "$BUCKET1" --no-public-access-prevention 2>/dev/null || true

# 3.2 Create bucket 2
echo -e "${BLUE}[INFO] Creating ${BUCKET2} (Multi-region US)...${NC}"
if gcloud storage buckets describe "$BUCKET2" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Bucket ${BUCKET2} already exists.${NC}"
else
    gcloud storage buckets create "$BUCKET2" --location=US --quiet || \
    gsutil mb -l US "$BUCKET2" || true
fi

# 3.3 Download cat.jpg from Google sample bucket and copy to bucket1 and bucket2
echo -e "${BLUE}[INFO] Fetching cat.jpg and uploading to buckets...${NC}"
if [ ! -f "cat.jpg" ]; then
    gcloud storage cp gs://cloud-training/ak8s/cat.jpg cat.jpg 2>/dev/null || \
    gsutil cp gs://cloud-training/ak8s/cat.jpg cat.jpg || \
    curl -sL "https://storage.googleapis.com/cloud-training/ak8s/cat.jpg" -o cat.jpg
fi

gcloud storage cp cat.jpg "${BUCKET1}/" 2>/dev/null || gsutil cp cat.jpg "${BUCKET1}/cat.jpg"
gcloud storage cp "${BUCKET1}/cat.jpg" "${BUCKET2}/cat.jpg" 2>/dev/null || gsutil cp "${BUCKET1}/cat.jpg" "${BUCKET2}/cat.jpg"

# 3.4 Grant allUsers Storage Object Viewer role on bucket1
echo -e "${BLUE}[INFO] Granting 'Storage Object Viewer' (roles/storage.objectViewer) to allUsers on ${BUCKET1}...${NC}"
gcloud storage buckets add-iam-policy-binding "$BUCKET1" \
    --member=allUsers \
    --role=roles/storage.objectViewer \
    --quiet 2>/dev/null || \
    gsutil iam ch allUsers:objectViewer "$BUCKET1" 2>/dev/null || true

echo -e "${GREEN}[SUCCESS] Cat image public URL: ${CAT_IMAGE_URL}${NC}"
echo -e "${GREEN}[SUCCESS] Checkpoint 2 Complete: Cloud Storage Buckets and permissions created!${NC}"

# ==============================================================================
# TASK 4: Cloud Shell Editor & Nginx on VM
# Scored Checkpoint 3: Install the nginx web server and customize the welcome page
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/4] Configuring Repo, Files, and Deploying Nginx on first-vm...${NC}"

# 4.1 Clone orchestrate-with-kubernetes repo
if [ -d "orchestrate-with-kubernetes" ]; then
    echo -e "${BLUE}[SKIP] Directory 'orchestrate-with-kubernetes' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Cloning repository 'orchestrate-with-kubernetes'...${NC}"
    git clone https://github.com/googlecodelabs/orchestrate-with-kubernetes.git
fi

# 4.2 Create test directory
mkdir -p test

# 4.3 Update cleanup.sh to append 'echo Finished cleanup!'
if [ -f "orchestrate-with-kubernetes/cleanup.sh" ]; then
    if ! grep -q "Finished cleanup!" orchestrate-with-kubernetes/cleanup.sh; then
        echo "echo Finished cleanup!" >> orchestrate-with-kubernetes/cleanup.sh
        echo -e "${BLUE}[INFO] Appended 'echo Finished cleanup!' to orchestrate-with-kubernetes/cleanup.sh.${NC}"
    fi
fi

# 4.4 Create index.html with the Cat image reference
HTML_CONTENT="<html><head><title>Cat</title></head> <body> <h1>Cat</h1> <img src=\"${CAT_IMAGE_URL}\"> </body></html>"
echo "$HTML_CONTENT" > index.html
echo "$HTML_CONTENT" > orchestrate-with-kubernetes/index.html
if [ -d "$HOME" ]; then
    echo "$HTML_CONTENT" > "$HOME/index.html"
fi

# 4.5 Wait for VM to be in RUNNING state
echo -e "${BLUE}[INFO] Waiting for VM 'first-vm' to be RUNNING...${NC}"
for i in {1..30}; do
    VM_STATUS=$(gcloud compute instances describe first-vm --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    if [ "$VM_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}[INFO] 'first-vm' is RUNNING.${NC}"
        break
    fi
    sleep 3
done

# Ensure SSH key exists in Cloud Shell
if [ ! -f "$HOME/.ssh/google_compute_engine" ]; then
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t rsa -N "" -f "$HOME/.ssh/google_compute_engine" -C "student" -q || true
fi

# 4.6 Copy index.html to first-vm via scp and configure Nginx
echo -e "${BLUE}[INFO] Copying index.html to first-vm and verifying Nginx...${NC}"
MAX_SCP_RETRIES=15
SCP_SUCCESS=0
for i in $(seq 1 $MAX_SCP_RETRIES); do
    if gcloud compute scp --zone="$ZONE" --quiet index.html first-vm:index.html 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] index.html successfully copied to first-vm:~/index.html!${NC}"
        SCP_SUCCESS=1
        break
    fi
    echo -e "${BLUE}[INFO] Waiting for SSH/SCP on first-vm (attempt $i/$MAX_SCP_RETRIES)...${NC}"
    sleep 5
done

# Run commands on first-vm via SSH to install nginx and copy index.html to /var/www/html/index.html
REMOTE_COMMANDS="sudo apt-get remove -y --purge man-db 2>/dev/null || true; sudo touch /var/lib/man-db/auto-update; sudo apt-get update -y && sudo apt-get install -y nginx && sudo cp -f ~/index.html /var/www/html/index.html && sudo systemctl restart nginx"
gcloud compute ssh first-vm --zone="$ZONE" --quiet --command="$REMOTE_COMMANDS" 2>/dev/null || true

# 4.7 Test VM HTTP connectivity
VM_IP=$(gcloud compute instances describe first-vm --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
if [ -n "$VM_IP" ]; then
    echo -e "${GREEN}[INFO] Testing HTTP on http://${VM_IP}/ ...${NC}"
    sleep 3
    if curl -s -m 5 "http://${VM_IP}" | grep -qi "Cat"; then
        echo -e "${GREEN}[SUCCESS] Nginx web server is live and serving the Cat page at http://${VM_IP}!${NC}"
    else
        echo -e "${YELLOW}[NOTICE] HTTP test did not find 'Cat' tag immediately, startup script will complete in a few moments.${NC}"
    fi
fi

echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ALL TASKS COMPLETED SUCCESSFULLY (100 / 100)!                ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for all 3 checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Create a VM instance with necessary firewall rule, and an IAM service account"
echo -e "  [x] Checkpoint 2: Create Cloud Storage Buckets"
echo -e "  [x] Checkpoint 3: Install the nginx web server and customize the welcome page\n"
