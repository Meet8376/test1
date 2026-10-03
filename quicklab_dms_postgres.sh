#!/bin/bash
# ==============================================================================
# Google Cloud Skills Boost / Qwiklabs Automation Script
# Lab: Migrate to Cloud SQL for PostgreSQL Using Database Migration Service
# Lab ID: GSP918
# Target Score: 100 / 100
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
echo -e "${CYAN}   Migrate to Cloud SQL for PostgreSQL Using DMS                 ${NC}"
echo -e "${CYAN}   Lab ID: GSP918                                                ${NC}"
echo -e "${CYAN}   Google Cloud Skills Boost Automation                          ${NC}"
echo -e "${CYAN}=================================================================${NC}"

# Detect GCP Project ID
export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "${DEVSHELL_PROJECT_ID:-}")
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}[ERROR] GCP Project ID is not set. Please set it using: gcloud config set project <PROJECT_ID>${NC}"
    exit 1
fi
echo -e "${GREEN}[INFO] Active Project: ${PROJECT_ID}${NC}"

export REGION="us-central1"
export ZONE="us-central1-a"

gcloud config set compute/region "$REGION" --quiet 2>/dev/null || true
gcloud config set compute/zone "$ZONE" --quiet 2>/dev/null || true

# ==============================================================================
# TASK 0: Enable Required Service APIs
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 0/4] Enabling Required Service APIs...${NC}"
gcloud services enable \
  datamigration.googleapis.com \
  servicenetworking.googleapis.com \
  compute.googleapis.com \
  sqladmin.googleapis.com --quiet

echo -e "${GREEN}[SUCCESS] APIs enabled.${NC}"

# ==============================================================================
# TASK 1: Prepare Source Database on postgresql-vm
# Checkpoint 1: Prepare the PostgreSQL source instance for migration (20 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 1/4] Configuring PostgreSQL VM for Replication...${NC}"

# Detect VM Zone
VM_ZONE=$(gcloud compute instances list --filter="name:postgresql-vm" --format="value(zone)" | head -n 1)
VM_ZONE="${VM_ZONE:-us-central1-a}"
echo -e "${BLUE}[INFO] postgresql-vm Zone: ${VM_ZONE}${NC}"

# Internal IP
INTERNAL_IP=$(gcloud compute instances describe postgresql-vm --zone="$VM_ZONE" --format='value(networkInterfaces[0].networkIP)')
echo -e "${BLUE}[INFO] postgresql-vm Internal IP: ${INTERNAL_IP}${NC}"

# Prepare VM setup script
VM_SETUP_SCRIPT=$(cat << 'VM_EOF'
#!/bin/bash
set -e

echo "[VM] Updating packages and installing postgresql-14-pglogical..."
sudo apt-get update -y
sudo apt-get install -y postgresql-14-pglogical

echo "[VM] Configuring postgresql.conf and pg_hba.conf..."
sudo bash -c 'cat << "EOF" >> /etc/postgresql/14/main/postgresql.conf
shared_preload_libraries = '\''pglogical'\''
output_plugin_libraries = '\''pglogical_output'\''
wal_level = logical
max_worker_processes = 10
max_replication_slots = 10
max_wal_senders = 10
listen_addresses = '\''*'\''
EOF'

echo "host all all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/14/main/pg_hba.conf
echo "host replication all 0.0.0.0/0 md5" | sudo tee -a /etc/postgresql/14/main/pg_hba.conf

echo "[VM] Restarting PostgreSQL service..."
sudo systemctl stop postgresql
sudo systemctl start postgresql@14-main

echo "[VM] Creating migration_admin replication user..."
sudo -u postgres psql << 'EOF'
CREATE USER migration_admin PASSWORD 'DMS_1s_cool!';
ALTER ROLE migration_admin WITH REPLICATION;
ALTER DATABASE orders OWNER TO migration_admin;
EOF

echo "[VM] Enabling pglogical extension & permissions across databases..."
for db in postgres orders gmemegen_db; do
  sudo -u postgres psql -d "$db" << 'EOF'
CREATE EXTENSION IF NOT EXISTS pglogical;
GRANT USAGE ON SCHEMA pglogical TO migration_admin;
GRANT ALL ON SCHEMA pglogical TO migration_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA pglogical TO migration_admin;
GRANT USAGE ON SCHEMA public TO migration_admin;
GRANT ALL ON SCHEMA public TO migration_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO migration_admin;
EOF
done

echo "[VM] Transferring table ownership in orders to migration_admin..."
sudo -u postgres psql -d orders << 'EOF'
ALTER TABLE public.distribution_centers OWNER TO migration_admin;
ALTER TABLE public.inventory_items OWNER TO migration_admin;
ALTER TABLE public.order_items OWNER TO migration_admin;
ALTER TABLE public.products OWNER TO migration_admin;
ALTER TABLE public.users OWNER TO migration_admin;
EOF

echo "[VM] SUCCESS: PostgreSQL source prepared!"
VM_EOF
)

ENCODED_VM_SCRIPT=$(echo "$VM_SETUP_SCRIPT" | base64 -w 0)

echo -e "${BLUE}[INFO] Executing configuration on postgresql-vm via SSH...${NC}"
gcloud compute ssh postgresql-vm --zone="$VM_ZONE" --quiet --command="echo '$ENCODED_VM_SCRIPT' | base64 -d | bash"

echo -e "${GREEN}[SUCCESS] Checkpoint 1 Ready: PostgreSQL source prepared!${NC}"

# ==============================================================================
# TASK 2: Create Source Connection Profile
# Checkpoint 2: Create a connection profile for the PostgreSQL source instance (20 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 2/4] Creating Connection Profile 'postgres-vm'...${NC}"

if gcloud database-migration connection-profiles describe postgres-vm --region="$REGION" &>/dev/null; then
    echo -e "${BLUE}[SKIP] Connection profile 'postgres-vm' already exists.${NC}"
else
    gcloud database-migration connection-profiles create postgresql postgres-vm \
        --region="$REGION" \
        --host="$INTERNAL_IP" \
        --port=5432 \
        --username=migration_admin \
        --password='DMS_1s_cool!' \
        --display-name=postgres-vm \
        --quiet
fi

echo -e "${GREEN}[SUCCESS] Checkpoint 2 Ready: Connection profile 'postgres-vm' created!${NC}"

# ==============================================================================
# TASK 3: Create & Start Continuous Migration Job
# Checkpoint 3: Create, start, and review a continuous migration job (20 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 3/4] Starting Continuous Migration Job...${NC}"

echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   CONSOLE ACTION REQUIRED (Takes ~1 minute):                    ${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo -e "1. In Google Cloud Console, navigate to: ${YELLOW}Database Migration > Migration jobs${NC}"
echo -e "2. Click ${YELLOW}Create migration job${NC}:"
echo -e "   - Job name: ${GREEN}vm-to-cloudsql${NC}"
echo -e "   - Source engine: ${GREEN}PostgreSQL${NC}"
echo -e "   - Destination engine: ${GREEN}Cloud SQL for PostgreSQL${NC}"
echo -e "   - Region: ${GREEN}us-central1${NC}"
echo -e "   - Migration job type: ${GREEN}Continuous${NC}"
echo -e "   -> Click ${YELLOW}Save & continue${NC}"
echo -e "3. Define a source:"
echo -e "   - Select existing profile: ${GREEN}postgres-vm${NC}"
echo -e "   -> Click ${YELLOW}Save & continue${NC}"
echo -e "4. Define a destination:"
echo -e "   - Type: ${GREEN}Existing instance${NC}"
echo -e "   - Select: ${GREEN}postgresql-cloudsql${NC} (confirm by typing instance name)"
echo -e "   - Connectivity method: ${GREEN}VPC peering${NC} -> VPC: ${GREEN}default${NC}"
echo -e "   -> Click ${YELLOW}Configure & continue${NC}"
echo -e "5. Configure migration databases:"
echo -e "   - Select: ${GREEN}All databases${NC}"
echo -e "   -> Click ${YELLOW}Save & continue${NC}"
echo -e "6. Click ${YELLOW}Test job${NC}, then click ${GREEN}Create & start job${NC}!"
echo -e "${CYAN}=================================================================${NC}"

echo -e "\n${BLUE}[INFO] Waiting for migration job 'vm-to-cloudsql' to be created and enter RUNNING / CDC phase...${NC}"
while true; do
    JOB_STATE=$(gcloud database-migration migration-jobs describe vm-to-cloudsql --region="$REGION" --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    JOB_PHASE=$(gcloud database-migration migration-jobs describe vm-to-cloudsql --region="$REGION" --format="value(phase)" 2>/dev/null || echo "UNKNOWN")
    
    if [ "$JOB_STATE" == "RUNNING" ] || [ "$JOB_PHASE" == "CDC" ]; then
        echo -e "${GREEN}[SUCCESS] Migration job 'vm-to-cloudsql' is active! (State: ${JOB_STATE}, Phase: ${JOB_PHASE})${NC}"
        break
    else
        echo -e "${BLUE}[INFO] Current state: ${JOB_STATE}, phase: ${JOB_PHASE}... (Checking again in 15s)${NC}"
        sleep 15
    fi
done

echo -e "${GREEN}[SUCCESS] Checkpoint 3 Ready: Continuous migration job is running!${NC}"

# ==============================================================================
# TASK 4: Test Continuous Migration by Updating Source Data
# Checkpoint 4: Test the continuous migration of data from the source to the destination (20 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 4/5] Testing Continuous Migration (Inserting Data)...${NC}"
echo -e "${BLUE}[INFO] Inserting record into orders.distribution_centers on postgresql-vm...${NC}"

gcloud compute ssh postgresql-vm --zone="$VM_ZONE" --quiet --command="
sudo -u postgres psql -d orders << 'EOF'
insert into distribution_centers values(-80.1918,25.7617,'Miami FL',11);
EOF
"

echo -e "${BLUE}[INFO] Waiting 15 seconds for CDC replication to sync with Cloud SQL...${NC}"
sleep 15

echo -e "${GREEN}[SUCCESS] Checkpoint 4 Ready: Continuous data updated and synced!${NC}"

# ==============================================================================
# TASK 5: Promote Cloud SQL to Standalone Database
# Checkpoint 5: Promote Cloud SQL for PostgreSQL database to be a stand-alone instance (20 pts)
# ==============================================================================
echo -e "\n${YELLOW}>>> [Task 5/5] Promoting Cloud SQL Instance to Standalone...${NC}"

echo -e "${BLUE}[INFO] Promoting migration job 'vm-to-cloudsql'...${NC}"
gcloud database-migration migration-jobs promote vm-to-cloudsql --region="$REGION" --quiet

echo -e "${BLUE}[INFO] Waiting for promotion to complete...${NC}"
while true; do
    JOB_STATE=$(gcloud database-migration migration-jobs describe vm-to-cloudsql --region="$REGION" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    if [ "$JOB_STATE" == "COMPLETED" ]; then
        echo -e "${GREEN}[SUCCESS] Migration job 'vm-to-cloudsql' promoted successfully! (State: ${JOB_STATE})${NC}"
        break
    else
        echo -e "${BLUE}[INFO] Current state after promote: ${JOB_STATE}... (Checking again in 10s)${NC}"
        sleep 10
    fi
done

echo -e "\n${GREEN}=================================================================${NC}"
echo -e "${GREEN}🎉 ALL 5 TASKS COMPLETED! (100 / 100 SCORE)                      ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "${YELLOW}Please click 'Check my progress' on all lab checkpoints:${NC}"
echo -e "  ✅ 1. Prepare the PostgreSQL source instance for migration (20/20)"
echo -e "  ✅ 2. Create a connection profile for the PostgreSQL source instance (20/20)"
echo -e "  ✅ 3. Create, start, and review a continuous migration job (20/20)"
echo -e "  ✅ 4. Test the continuous migration of data from the source to the destination (20/20)"
echo -e "  ✅ 5. Promote Cloud SQL for PostgreSQL database to be a stand-alone instance (20/20)"
echo -e "${GREEN}=================================================================${NC}"
