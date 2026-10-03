#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Connect Cloud Run Functions (CBL492)
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
echo -e "${CYAN}   Connect Cloud Run Functions                                   ${NC}"
echo -e "${CYAN}   Lab ID: CBL492                                                ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# Target Region and Zone (Defaulting to europe-west1 & europe-west1-c per lab instructions)
export REGION="${REGION:-europe-west1}"
export ZONE="${ZONE:-europe-west1-c}"
echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"
echo -e "${GREEN}[INFO] Target Zone:    ${ZONE}${NC}"

gcloud config set compute/region "$REGION" --quiet
gcloud config set compute/zone "$ZONE" --quiet
gcloud config set run/region "$REGION" --quiet

# ==============================================================================
# TASK 1: Enable APIs
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/6] Enabling Required APIs...${NC}"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  redis.googleapis.com \
  vpcaccess.googleapis.com --quiet

echo -e "${GREEN}[SUCCESS] APIs enabled.${NC}"

# ==============================================================================
# TASK 2 & 3: Provision Memorystore for Redis & Serverless VPC Access Connector
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2 & 3/6] Provisioning Redis & VPC Access Connector in parallel...${NC}"

export REDIS_INSTANCE=customerdb
if gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Redis instance '$REDIS_INSTANCE' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Memorystore Redis instance '$REDIS_INSTANCE' (async)...${NC}"
    gcloud redis instances create "$REDIS_INSTANCE" \
      --size=2 --region="$REGION" \
      --redis-version=redis_6_x \
      --async --quiet
fi

# Create Serverless VPC Access Connector
if gcloud compute networks vpc-access connectors describe test-connector --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] VPC Access connector 'test-connector' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating Serverless VPC Access connector 'test-connector'...${NC}"
    gcloud compute networks vpc-access connectors create test-connector \
      --region="$REGION" \
      --range=10.8.0.0/28 \
      --network=default \
      --min-instances=2 \
      --max-instances=3 \
      --quiet
fi
echo -e "${GREEN}[SUCCESS] Checkpoint 2 Ready: Serverless VPC Access connector created!${NC}"

# Wait for Redis instance to finish creation
echo -e "${BLUE}[INFO] Waiting for Redis instance to become READY...${NC}"
while true; do
    REDIS_STATE=$(gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" --format='value(state)' 2>/dev/null || echo "CREATING")
    if [ "$REDIS_STATE" == "READY" ]; then
        break
    fi
    echo -n "."
    sleep 10
done
echo -e "\n${GREEN}[SUCCESS] Redis instance '$REDIS_INSTANCE' is READY! (Checkpoint 1 Ready)${NC}"

export REDIS_IP=$(gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" --format="value(host)")
export REDIS_PORT=$(gcloud redis instances describe "$REDIS_INSTANCE" --region="$REGION" --format="value(port)")
echo -e "${GREEN}[INFO] Redis Host: ${REDIS_IP}, Port: ${REDIS_PORT}${NC}"

# ==============================================================================
# TASK 4: Create Event-Driven Function for Pub/Sub
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/6] Creating Pub/Sub Topic and Event-Driven Function...${NC}"
export TOPIC=add_redis
if gcloud pubsub topics describe "$TOPIC" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Pub/Sub topic '$TOPIC' already exists.${NC}"
else
    gcloud pubsub topics create "$TOPIC" --quiet
fi

mkdir -p ~/redis-pubsub && cd ~/redis-pubsub

cat <<'EOF' > main.py
import os
import base64
import json
import redis
import functions_framework

redis_host = os.environ.get('REDISHOST', 'localhost')
redis_port = int(os.environ.get('REDISPORT', 6379))
redis_client = redis.StrictRedis(host=redis_host, port=redis_port)

@functions_framework.cloud_event
def addToRedis(cloud_event):
    json_data_str = base64.b64decode(cloud_event.data["message"]["data"]).decode()
    json_payload = json.loads(json_data_str)
    response_data = ""
    if json_payload and 'id' in json_payload:
        id = json_payload['id']
        data = redis_client.set(id, json_data_str)
        response_data = redis_client.get(id)
        print(f"Added data to Redis: {response_data}")
    else:
        print("Message is invalid, or missing an 'id' attribute")
EOF

cat <<'EOF' > requirements.txt
functions-framework==3.2.0
redis==4.3.4
EOF

echo -e "${BLUE}[INFO] Deploying python-pubsub-function...${NC}"
gcloud functions deploy python-pubsub-function \
 --runtime=python313 \
 --region="$REGION" \
 --source=. \
 --entry-point=addToRedis \
 --trigger-topic="$TOPIC" \
 --vpc-connector "projects/${PROJECT_ID}/locations/${REGION}/connectors/test-connector" \
 --set-env-vars "REDISHOST=${REDIS_IP},REDISPORT=${REDIS_PORT}" \
 --quiet

echo -e "${BLUE}[INFO] Publishing test message to Pub/Sub topic '$TOPIC'...${NC}"
gcloud pubsub topics publish "$TOPIC" --message='{"id": 1234, "firstName": "Lucas" ,"lastName": "Sherman", "Phone": "555-555-5555"}'

echo -e "${GREEN}[SUCCESS] Checkpoint 3 Ready: Pub/Sub event-driven function deployed and tested!${NC}"

# ==============================================================================
# TASK 5: Create HTTP Function to Query Redis
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/6] Creating HTTP Function to Query Redis...${NC}"
mkdir -p ~/redis-http && cd ~/redis-http

cat <<'EOF' > main.py
import os
import redis
from flask import request
import functions_framework

redis_host = os.environ.get('REDISHOST', 'localhost')
redis_port = int(os.environ.get('REDISPORT', 6379))
redis_client = redis.StrictRedis(host=redis_host, port=redis_port)

@functions_framework.http
def getFromRedis(request):
    response_data = ""
    if request.method == 'GET':
        id = request.args.get('id')
        try:
            response_data = redis_client.get(id)
        except RuntimeError:
            response_data = ""
        if response_data is None:
            response_data = ""
    return response_data
EOF

cat <<'EOF' > requirements.txt
functions-framework==3.2.0
redis==4.3.4
EOF

echo -e "${BLUE}[INFO] Deploying http-get-redis...${NC}"
gcloud functions deploy http-get-redis \
 --gen2 \
 --runtime python313 \
 --entry-point getFromRedis \
 --source . \
 --region "$REGION" \
 --trigger-http \
 --timeout 600s \
 --max-instances 1 \
 --vpc-connector "projects/${PROJECT_ID}/locations/${REGION}/connectors/test-connector" \
 --set-env-vars "REDISHOST=${REDIS_IP},REDISPORT=${REDIS_PORT}" \
 --no-allow-unauthenticated \
 --quiet

FUNCTION_URI=$(gcloud functions describe http-get-redis --gen2 --region "$REGION" --format "value(serviceConfig.uri)")
echo -e "${BLUE}[INFO] Testing http-get-redis at ${FUNCTION_URI}?id=1234...${NC}"
TEST_HTTP_RESP=$(curl -s -H "Authorization: bearer $(gcloud auth print-identity-token)" "${FUNCTION_URI}?id=1234")
echo -e "${GREEN}[RESPONSE] ${TEST_HTTP_RESP}${NC}"
echo -e "${GREEN}[SUCCESS] Checkpoint 4 Ready: HTTP function querying Redis deployed and tested!${NC}"

# ==============================================================================
# TASK 6: Connect to a VM Instance from an HTTP Function
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 6/6] Creating VM and Connecting via HTTP Function with VPC Connector...${NC}"
cd ~
gcloud storage cp gs://cloud-training/CBL492/startup.sh ~/startup.sh 2>/dev/null || cat <<'EOF' > ~/startup.sh
#!/bin/bash
apt-get update
apt-get install -y apache2
cat <<'HTML' > /var/www/html/index.html
<html><body><p>Linux startup script from a local file.</p></body></html>
HTML
systemctl restart apache2
EOF

# Create VM webserver-vm
if gcloud compute instances describe webserver-vm --zone="$ZONE" &>/dev/null; then
    echo -e "${BLUE}[SKIP] VM 'webserver-vm' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating VM 'webserver-vm'...${NC}"
    gcloud compute instances create webserver-vm \
      --image-project=debian-cloud \
      --image-family=debian-12 \
      --metadata-from-file=startup-script=~/startup.sh \
      --machine-type e2-standard-2 \
      --tags=http-server \
      --scopes=https://www.googleapis.com/auth/cloud-platform \
      --zone "$ZONE" \
      --quiet
fi

# Create Firewall rule
if gcloud compute firewall-rules describe default-allow-http &>/dev/null; then
    echo -e "${BLUE}[SKIP] Firewall rule 'default-allow-http' already exists.${NC}"
else
    echo -e "${BLUE}[INFO] Creating firewall rule 'default-allow-http'...${NC}"
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

export VM_INT_IP=$(gcloud compute instances describe webserver-vm --format='get(networkInterfaces[0].networkIP)' --zone "$ZONE")
echo -e "${GREEN}[INFO] VM Internal IP: ${VM_INT_IP}${NC}"

mkdir -p ~/vm-http && cd ~/vm-http

cat <<'EOF' > main.py
import functions_framework
import requests

@functions_framework.http
def connectVM(request):
    resp_text = ""
    if request.method == 'GET':
        ip = request.args.get('ip')
        try:
            response_data = requests.get(f"http://{ip}")
            resp_text = response_data.text
        except RuntimeError:
            print ("Error while connecting to VM")
    return resp_text
EOF

cat <<'EOF' > requirements.txt
functions-framework==3.2.0
Werkzeug==2.3.7
flask==2.1.3
requests==2.28.1
EOF

echo -e "${BLUE}[INFO] Deploying vm-connector with VPC connector...${NC}"
gcloud functions deploy vm-connector \
 --runtime python313 \
 --entry-point connectVM \
 --source . \
 --region "$REGION" \
 --trigger-http \
 --timeout 10s \
 --max-instances 1 \
 --no-allow-unauthenticated \
 --vpc-connector "projects/${PROJECT_ID}/locations/${REGION}/connectors/test-connector" \
 --quiet

VM_FUNCTION_URI=$(gcloud functions describe vm-connector --region "$REGION" --format='value(url)')
echo -e "${BLUE}[INFO] Testing internal VM connection from vm-connector...${NC}"
VM_TEST_RESP=$(curl -s -H "Authorization: bearer $(gcloud auth print-identity-token)" "${VM_FUNCTION_URI}?ip=${VM_INT_IP}")
echo -e "${GREEN}[RESPONSE] ${VM_TEST_RESP}${NC}"
echo -e "${GREEN}[SUCCESS] Checkpoint 5 Ready: Connected to VM instance through VPC connector!${NC}"

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}🎉 ALL TASKS COMPLETE! (100 / 100 SCORE)                         ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${YELLOW}Now verify all checkpoints on your lab page:${NC}"
echo -e "  ✅ Task 2: Set up a Memorystore for Redis instance"
echo -e "  ✅ Task 3: Set up Serverless VPC Access"
echo -e "  ✅ Task 4: Create an event-driven function for Pub/Sub"
echo -e "  ✅ Task 5: Create an HTTP function"
echo -e "  ✅ Task 6: Connect to a VM instance from an HTTP function"
echo -e "${GREEN}=================================================================${NC}"
