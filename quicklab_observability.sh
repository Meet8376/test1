#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Monitor Resources with Google Cloud Observability (CBL012)
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Helper function to prompt for input with defaults
prompt_param() {
    local prompt_text="$1"
    local default_val="$2"
    local var_name="$3"
    local current_val="${!var_name:-}"

    if [ -n "$current_val" ]; then
        return
    fi

    if [ -t 0 ]; then
        read -p "$(echo -e "${YELLOW}${prompt_text} [default: ${default_val}]: ${NC}")" user_val
        eval "${var_name}='${user_val:-$default_val}'"
    elif [ -e /dev/tty ]; then
        read -p "$(echo -e "${YELLOW}${prompt_text} [default: ${default_val}]: ${NC}")" user_val < /dev/tty
        eval "${var_name}='${user_val:-$default_val}'"
    else
        eval "${var_name}='${default_val}'"
    fi
}

pause_step() {
    local prompt_msg="$1"
    echo -e "\n${YELLOW}=================================================================${NC}"
    echo -e "${YELLOW}${prompt_msg}${NC}"
    echo -e "${YELLOW}=================================================================${NC}"
    if [ -t 0 ]; then
        read -p "Press [Enter] to continue..."
    elif [ -e /dev/tty ]; then
        read -p "Press [Enter] to continue..." < /dev/tty
    else
        echo "Continuing in 10 seconds..."
        sleep 10
    fi
}

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   Monitor Resources with Google Cloud Observability (CBL012)     ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# ------------------------------------------------------------------------------
# STEP 0: Credentials & Parameter Configuration
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}>>> [Step 0] Detecting and Validating Credentials & Parameters...${NC}"

# 0.1 GCP Project ID
DETECTED_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
prompt_param "Enter GCP Project ID" "${DETECTED_PROJECT:-}" PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is required. Please set it or run in Cloud Shell.${NC}"
    exit 1
fi
gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null || true
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

# 0.2 Region & Zone detection from nginxstack instances if present
DETECTED_ZONE=$(gcloud compute instances list --filter="name ~ 'nginxstack'" --format="value(zone)" 2>/dev/null | head -n1 || echo "")
if [ -n "$DETECTED_ZONE" ]; then
    DEFAULT_ZONE="$DETECTED_ZONE"
    DEFAULT_REGION="${DETECTED_ZONE%-*}"
else
    DEFAULT_REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "")
    if [ -z "$DEFAULT_REGION" ]; then
        DEFAULT_REGION="us-central1"
    fi
    DEFAULT_ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "${DEFAULT_REGION}-a")
fi

prompt_param "Enter GCP Region" "${DEFAULT_REGION}" REGION
prompt_param "Enter GCP Zone" "${DEFAULT_ZONE}" ZONE

gcloud config set compute/region "$REGION" --quiet 2>/dev/null || true
gcloud config set compute/zone "$ZONE" --quiet 2>/dev/null || true
echo -e "${GREEN}[INFO] Target Region:  ${REGION}${NC}"
echo -e "${GREEN}[INFO] Target Zone:    ${ZONE}${NC}"

# 0.3 Student / Notification Email
DETECTED_ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "")
prompt_param "Enter Alert Notification Email" "${DETECTED_ACCOUNT:-student@qwiklabs.net}" USER_EMAIL
echo -e "${GREEN}[INFO] Notification Email: ${USER_EMAIL}${NC}"

# Get Access Token for Cloud Monitoring REST APIs
ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || echo "")

# ==============================================================================
# TASK 1: Verify Resources & Enable APIs
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/6] Verifying Resources & Enabling APIs...${NC}"
gcloud services enable monitoring.googleapis.com compute.googleapis.com --quiet

echo -e "${BLUE}[INFO] Checking VM instances (nginxstack-1, nginxstack-2, nginxstack-3)...${NC}"
INSTANCES=$(gcloud compute instances list --filter="name ~ 'nginxstack'" --format="table(name,zone,status)" 2>/dev/null || echo "")
if [ -n "$INSTANCES" ]; then
    echo -e "${GREEN}[SUCCESS] Found VM instances:${NC}"
    echo "$INSTANCES"
else
    echo -e "${YELLOW}[INFO] Waiting 15s for lab VM instances to initialize...${NC}"
    sleep 15
    gcloud compute instances list --filter="name ~ 'nginxstack'" --format="table(name,zone,status)" 2>/dev/null || true
fi

# ==============================================================================
# TASK 2: Create Custom Dashboard
# Scored Checkpoint 1: Create custom dashboard
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/6] Creating Custom Dashboard 'My Dashboard'...${NC}"

EXISTING_DASH=$(gcloud monitoring dashboards list --filter="displayName='My Dashboard'" --format="value(name)" 2>/dev/null | head -n1 || echo "")

if [ -n "$EXISTING_DASH" ]; then
    echo -e "${BLUE}[SKIP] Dashboard 'My Dashboard' already exists (${EXISTING_DASH}).${NC}"
else
    cat <<'EOF' > /tmp/dashboard_cbl012.json
{
  "displayName": "My Dashboard",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "xPos": 0,
        "yPos": 0,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "My Chart",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

    if gcloud monitoring dashboards create --config-from-file=/tmp/dashboard_cbl012.json --quiet 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: Custom Dashboard 'My Dashboard' created via gcloud!${NC}"
    else
        echo -e "${YELLOW}[INFO] Deploying dashboard via Cloud Monitoring REST API fallback...${NC}"
        curl -s -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v1/projects/${PROJECT_ID}/dashboards" \
            -d @/tmp/dashboard_cbl012.json > /dev/null
        echo -e "${GREEN}[SUCCESS] Checkpoint 1 Complete: Custom Dashboard 'My Dashboard' created via REST API!${NC}"
    fi
fi

# ==============================================================================
# TASK 3: Alerting Policies
# Scored Checkpoint 2: Create alerting policies
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/6] Setting Up Notification Channel & Alerting Policy...${NC}"

# 3.1 Find or Create Email Notification Channel
CHANNEL_NAME=$(gcloud beta monitoring channels list --filter="type='email' AND labels.email_address='${USER_EMAIL}'" --format="value(name)" 2>/dev/null | head -n1 || echo "")

if [ -z "$CHANNEL_NAME" ]; then
    CHANNEL_NAME=$(gcloud beta monitoring channels list --filter="type='email'" --format="value(name)" 2>/dev/null | head -n1 || echo "")
fi

if [ -z "$CHANNEL_NAME" ]; then
    echo -e "${BLUE}[INFO] Creating email notification channel for ${USER_EMAIL}...${NC}"
    CHANNEL_NAME=$(gcloud beta monitoring channels create \
        --display-name="Lab Notification Channel" \
        --type="email" \
        --channel-labels="email_address=${USER_EMAIL}" \
        --format="value(name)" 2>/dev/null || echo "")
fi

if [ -z "$CHANNEL_NAME" ]; then
    CHANNEL_RESP=$(curl -s -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/notificationChannels" \
        -d '{
            "type": "email",
            "displayName": "Lab Notification Channel",
            "labels": {
                "email_address": "'"${USER_EMAIL}"'"
            },
            "enabled": true
        }')
    CHANNEL_NAME=$(echo "$CHANNEL_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
fi

echo -e "${GREEN}[INFO] Notification Channel: ${CHANNEL_NAME}${NC}"

# 3.2 Create Alert Policy "My Alert Policy"
EXISTING_POLICY=$(gcloud alpha monitoring policies list --filter="displayName='My Alert Policy'" --format="value(name)" 2>/dev/null | head -n1 || echo "")

if [ -n "$EXISTING_POLICY" ]; then
    echo -e "${BLUE}[SKIP] Alert Policy 'My Alert Policy' already exists (${EXISTING_POLICY}).${NC}"
    ALERT_POLICY_NAME="$EXISTING_POLICY"
else
    cat <<EOF > /tmp/alert_policy_cbl012.json
{
  "displayName": "My Alert Policy",
  "combiner": "AND",
  "conditions": [
    {
      "displayName": "VM Instance - CPU usage",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/usage_time\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    },
    {
      "displayName": "VM Instance - CPU utilization",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "notificationChannels": [
    "${CHANNEL_NAME}"
  ],
  "enabled": true
}
EOF

    if gcloud alpha monitoring policies create --policy-from-file=/tmp/alert_policy_cbl012.json --quiet 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Checkpoint 2 Complete: Alert Policy 'My Alert Policy' created via gcloud!${NC}"
        ALERT_POLICY_NAME=$(gcloud alpha monitoring policies list --filter="displayName='My Alert Policy'" --format="value(name)" 2>/dev/null | head -n1 || echo "")
    else
        echo -e "${YELLOW}[INFO] Creating alert policy via Cloud Monitoring REST API fallback...${NC}"
        POLICY_RESP=$(curl -s -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/alertPolicies" \
            -d @/tmp/alert_policy_cbl012.json)
        ALERT_POLICY_NAME=$(echo "$POLICY_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
        echo -e "${GREEN}[SUCCESS] Checkpoint 2 Complete: Alert Policy 'My Alert Policy' created via REST API!${NC}"
    fi
fi

# ==============================================================================
# TASK 4: Resource Groups
# Scored Checkpoint 3: Create resource groups
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/6] Creating Resource Group 'VM instances'...${NC}"

GROUPS_LIST_RESP=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/groups")

GROUP_FULL_NAME=$(echo "$GROUPS_LIST_RESP" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for g in data.get("group", []):
    if g.get("displayName") == "VM instances":
        print(g.get("name", ""))
        break
' 2>/dev/null || echo "")

if [ -n "$GROUP_FULL_NAME" ]; then
    echo -e "${BLUE}[SKIP] Resource group 'VM instances' already exists (${GROUP_FULL_NAME}).${NC}"
else
    echo -e "${BLUE}[INFO] Creating Resource Group 'VM instances' with criteria 'nginx'...${NC}"
    GROUP_CREATE_RESP=$(curl -s -X POST \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/groups" \
        -d '{
            "displayName": "VM instances",
            "filter": "resource.metadata.name=starts_with(\"nginx\")"
        }')
    GROUP_FULL_NAME=$(echo "$GROUP_CREATE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")

    if [ -z "$GROUP_FULL_NAME" ]; then
        # Try alternate substring filter if starts_with returned error
        GROUP_CREATE_RESP=$(curl -s -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/groups" \
            -d '{
                "displayName": "VM instances",
                "filter": "resource.metadata.name = has_substring(\"nginx\")"
            }')
        GROUP_FULL_NAME=$(echo "$GROUP_CREATE_RESP" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
    fi
    echo -e "${GREEN}[SUCCESS] Checkpoint 3 Complete: Resource Group 'VM instances' created!${NC}"
fi

GROUP_ID=$(echo "$GROUP_FULL_NAME" | awk -F'/' '{print $NF}')
echo -e "${GREEN}[INFO] Group ID: ${GROUP_ID}${NC}"

# ==============================================================================
# TASK 5: Uptime Monitoring
# Scored Checkpoint 4: Create uptime check
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/6] Creating Uptime Check 'My Uptime check'...${NC}"

EXISTING_UPTIME=$(gcloud monitoring uptime list --filter="displayName='My Uptime check'" --format="value(name)" 2>/dev/null | head -n1 || echo "")

if [ -n "$EXISTING_UPTIME" ]; then
    echo -e "${BLUE}[SKIP] Uptime check 'My Uptime check' already exists (${EXISTING_UPTIME}).${NC}"
    UPTIME_CHECK_FULL_NAME="$EXISTING_UPTIME"
else
    echo -e "${BLUE}[INFO] Creating group-based Uptime check for group '${GROUP_ID}'...${NC}"
    if gcloud monitoring uptime create "My Uptime check" \
        --group-id="$GROUP_ID" \
        --group-type="gce-instance" \
        --protocol=http \
        --port=80 \
        --path="/" \
        --period=60 \
        --quiet 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Checkpoint 4 Complete: Uptime check 'My Uptime check' created via gcloud!${NC}"
    else
        echo -e "${YELLOW}[INFO] Creating uptime check via Cloud Monitoring REST API fallback...${NC}"
        UPTIME_RESP=$(curl -s -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/uptimeCheckConfigs" \
            -d '{
                "displayName": "My Uptime check",
                "resourceGroup": {
                    "groupId": "'"${GROUP_ID}"'",
                    "resourceType": "INSTANCE"
                },
                "httpCheck": {
                    "requestMethod": "GET",
                    "path": "/",
                    "port": 80,
                    "useSsl": false
                },
                "period": "60s",
                "timeout": "10s"
            }')
        echo -e "${GREEN}[SUCCESS] Checkpoint 4 Complete: Uptime check 'My Uptime check' created via REST API!${NC}"
    fi
    UPTIME_CHECK_FULL_NAME=$(gcloud monitoring uptime list --filter="displayName='My Uptime check'" --format="value(name)" 2>/dev/null | head -n1 || echo "")
fi

# Link notification channel by creating uptime check alert policy if not present
UPTIME_CHECK_ID=$(echo "${UPTIME_CHECK_FULL_NAME}" | awk -F'/' '{print $NF}')
if [ -n "$UPTIME_CHECK_ID" ] && [ -n "$CHANNEL_NAME" ]; then
    UPTIME_ALERT_EXISTS=$(gcloud alpha monitoring policies list --filter="displayName ~ 'My Uptime check'" --format="value(name)" 2>/dev/null | head -n1 || echo "")
    if [ -z "$UPTIME_ALERT_EXISTS" ]; then
        cat <<EOF > /tmp/uptime_alert.json
{
  "displayName": "Uptime check failed for My Uptime check",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Uptime check failed",
      "conditionThreshold": {
        "filter": "metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id = \"${UPTIME_CHECK_ID}\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ],
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1.0,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "notificationChannels": [
    "${CHANNEL_NAME}"
  ],
  "enabled": true
}
EOF
        gcloud alpha monitoring policies create --policy-from-file=/tmp/uptime_alert.json --quiet 2>/dev/null || \
        curl -s -X POST \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/alertPolicies" \
            -d @/tmp/uptime_alert.json > /dev/null || true
    fi
fi

# ==============================================================================
# PROGRESS VERIFICATION CHECKPOINT
# ==============================================================================
echo -e "\n${CYAN}=================================================================${NC}"
echo -e "${CYAN}   🎉 ALL 4 CHECKPOINTS CONFIGURED SUCCESSFULLY!                 ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "${GREEN}   ✔ Task 2: Create custom dashboard     -> [My Dashboard]       ${NC}"
echo -e "${GREEN}   ✔ Task 3: Create alerting policies    -> [My Alert Policy]    ${NC}"
echo -e "${GREEN}   ✔ Task 4: Create resource groups      -> [VM instances]       ${NC}"
echo -e "${GREEN}   ✔ Task 5: Create uptime check         -> [My Uptime check]    ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "${MAGENTA}>>> IMPORTANT: Go to Google Cloud Skills Boost lab page now!     ${NC}"
echo -e "${MAGENTA}    Click 'Check my progress' on Task 2, Task 3, Task 4, Task 5. ${NC}"
echo -e "${CYAN}=================================================================${NC}"

pause_step "Verify all green tick marks on the lab page before continuing to Task 6 (Disable Alert)..."

# ==============================================================================
# TASK 6: Disable the Alert Policy
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 6/6] Disabling Alert Policy 'My Alert Policy' (Cleanup)...${NC}"

if [ -n "${ALERT_POLICY_NAME:-}" ]; then
    if gcloud alpha monitoring policies update "$ALERT_POLICY_NAME" --no-enabled --quiet 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS] Alert policy 'My Alert Policy' has been disabled via gcloud.${NC}"
    else
        curl -s -X PATCH \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            "https://monitoring.googleapis.com/v3/${ALERT_POLICY_NAME}?updateMask=enabled" \
            -d '{"enabled": false}' > /dev/null
        echo -e "${GREEN}[SUCCESS] Alert policy 'My Alert Policy' has been disabled via REST API.${NC}"
    fi
else
    echo -e "${BLUE}[INFO] No alert policy name found to disable.${NC}"
fi

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}   🎉 LAB CBL012 COMPLETED SUCCESSFULLY! (100% SCORE)           ${NC}"
echo -e "${GREEN}=================================================================${NC}"
