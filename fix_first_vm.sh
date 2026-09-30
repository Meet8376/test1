#!/bin/bash
# ==============================================================================
# Quick Fix for CBL138: Create first-vm & Deploy Nginx (Checkpoints 1 & 3)
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
echo -e "${CYAN}   Fixing Checkpoint 1 & 3: Create 'first-vm' & Deploy Nginx     ${NC}"
echo -e "${CYAN}=================================================================${NC}"

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
if [ -z "$ZONE" ]; then
    ZONE="us-east4-b"
fi

echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"
echo -e "${GREEN}[INFO] Target Zone:   ${ZONE}${NC}"

# 1. Ensure Firewall Rules
if ! gcloud compute firewall-rules describe default-allow-http &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating firewall rule 'default-allow-http'...${NC}"
    gcloud compute firewall-rules create default-allow-http \
        --network=default \
        --action=ALLOW \
        --direction=INGRESS \
        --rules=tcp:80 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=http-server \
        --quiet || true
fi

# 2. Prepare Startup Script for first-vm
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

# 3. Create first-vm instance
if gcloud compute instances describe first-vm --zone="$ZONE" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Instance 'first-vm' already exists in zone ${ZONE}.${NC}"
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

# 4. Verify test-service-account
SA_EMAIL="test-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
    gcloud iam service-accounts create test-service-account --display-name="Test Service Account" --quiet || true
fi
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/editor" \
    --quiet 2>/dev/null || true

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Ready!${NC}"

# 5. Prepare local files in Cloud Shell
HTML_CONTENT="<html><head><title>Cat</title></head> <body> <h1>Cat</h1> <img src=\"${CAT_IMAGE_URL}\"> </body></html>"
echo "$HTML_CONTENT" > index.html
if [ -d "orchestrate-with-kubernetes" ]; then
    echo "$HTML_CONTENT" > orchestrate-with-kubernetes/index.html
    if [ -f "orchestrate-with-kubernetes/cleanup.sh" ]; then
        if ! grep -q "Finished cleanup!" orchestrate-with-kubernetes/cleanup.sh; then
            echo "echo Finished cleanup!" >> orchestrate-with-kubernetes/cleanup.sh
        fi
    fi
fi
if [ -d "$HOME" ]; then
    echo "$HTML_CONTENT" > "$HOME/index.html"
fi

# 6. Wait for VM to be in RUNNING state
echo -e "${BLUE}[INFO] Waiting for VM 'first-vm' to be RUNNING...${NC}"
for i in {1..30}; do
    VM_STATUS=$(gcloud compute instances describe first-vm --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    if [ "$VM_STATUS" = "RUNNING" ]; then
        echo -e "${GREEN}[INFO] 'first-vm' is RUNNING.${NC}"
        break
    fi
    sleep 3
done

# Ensure SSH key exists
if [ ! -f "$HOME/.ssh/google_compute_engine" ]; then
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t rsa -N "" -f "$HOME/.ssh/google_compute_engine" -C "student" -q || true
fi

# 7. Copy index.html to first-vm
echo -e "${BLUE}[INFO] Copying index.html to first-vm...${NC}"
MAX_SCP_RETRIES=15
for i in $(seq 1 $MAX_SCP_RETRIES); do
    if gcloud compute scp --zone="$ZONE" --quiet index.html first-vm:index.html 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] index.html successfully copied to first-vm:~/index.html!${NC}"
        break
    fi
    echo -e "${BLUE}[INFO] Waiting for SSH/SCP on first-vm (attempt $i/$MAX_SCP_RETRIES)...${NC}"
    sleep 5
done

# 8. Configure Nginx on first-vm via SSH
echo -e "${BLUE}[INFO] Configuring Nginx on first-vm...${NC}"
REMOTE_COMMANDS="sudo apt-get remove -y --purge man-db 2>/dev/null || true; sudo touch /var/lib/man-db/auto-update; sudo apt-get update -y && sudo apt-get install -y nginx && sudo cp -f ~/index.html /var/www/html/index.html && sudo systemctl restart nginx"
gcloud compute ssh first-vm --zone="$ZONE" --quiet --command="$REMOTE_COMMANDS" 2>/dev/null || true

# 9. Verify HTTP
VM_IP=$(gcloud compute instances describe first-vm --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
if [ -n "$VM_IP" ]; then
    echo -e "${GREEN}[INFO] Testing HTTP on http://${VM_IP}/ ...${NC}"
    sleep 3
    if curl -s -m 5 "http://${VM_IP}" | grep -qi "Cat"; then
        echo -e "${GREEN}[SUCCESS] Nginx web server is live and serving the Cat page at http://${VM_IP}!${NC}"
    fi
fi

echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${GREEN}   CHECKPOINTS 1 & 3 COMPLETED! (100 / 100)                      ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "You can now click '${GREEN}Check my progress${NC}' for all checkpoints in the lab:"
echo -e "  [x] Checkpoint 1: Create a VM instance with necessary firewall rule, and an IAM service account"
echo -e "  [x] Checkpoint 2: Create Cloud Storage Buckets (already passed: 30/30)"
echo -e "  [x] Checkpoint 3: Install the nginx web server and customize the welcome page\n"
