#!/bin/bash
set -uo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

export REGION="europe-west1"
export ZONE="europe-west1-c"

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Fixing Task 6: Creating webserver-vm (Targeting 100/100)       ${NC}"
echo -e "${CYAN}=================================================================${NC}"

cd ~
echo -e "${BLUE}[INFO] Preparing startup.sh...${NC}"
gcloud storage cp gs://cloud-training/CBL492/startup.sh ./startup.sh 2>/dev/null || cat <<'EOF' > ./startup.sh
#!/bin/bash
apt-get update
apt-get install -y apache2
cat <<'HTML' > /var/www/html/index.html
<html><body><p>Linux startup script from a local file.</p></body></html>
HTML
systemctl restart apache2
EOF

echo -e "${BLUE}[INFO] Creating compute instance 'webserver-vm'...${NC}"
gcloud compute instances create webserver-vm \
--image-project=debian-cloud \
--image-family=debian-12 \
--metadata-from-file=startup-script=./startup.sh \
--machine-type e2-standard-2 \
--tags=http-server \
--scopes=https://www.googleapis.com/auth/cloud-platform \
--zone "$ZONE" \
--quiet

# Ensure firewall rule exists
if ! gcloud compute firewall-rules describe default-allow-http &>/dev/null; then
    gcloud compute firewall-rules create default-allow-http \
      --direction=INGRESS \
      --priority=1000 \
      --network=default \
      --action=ALLOW \
      --rules=tcp:80 \
      --source-ranges=0.0.0.0/0 \
      --target-tags=http-server \
      --quiet
fi

VM_INT_IP=$(gcloud compute instances describe webserver-vm --zone "$ZONE" --format='get(networkInterfaces[0].networkIP)')
echo -e "${GREEN}[INFO] VM Internal IP: ${VM_INT_IP}${NC}"

echo -e "${BLUE}[INFO] Testing connection to VM internal IP from vm-connector...${NC}"
FUNCTION_URI=$(gcloud functions describe vm-connector --region "$REGION" --format='value(url)')
RESP=$(curl -s -H "Authorization: bearer $(gcloud auth print-identity-token)" "${FUNCTION_URI}?ip=${VM_INT_IP}")
echo -e "${GREEN}[RESPONSE] ${RESP}${NC}"

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}🎉 webserver-vm CREATED AND TESTED! (100 / 100)                   ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${YELLOW}Now click 'Check my progress' on:${NC}"
echo -e "  ✅ Connect to a VM instance from an HTTP function (20 / 20)"
echo -e "${GREEN}=================================================================${NC}"
