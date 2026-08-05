#!/bin/bash
# =============================================================================
# user_data.sh — Boot script for EC2 instance
#
# WHAT THIS DOES:
#   Runs automatically when the EC2 instance launches. It:
#   1. Adds 2 GB of swap space (CRITICAL: t3.medium has only 4 GB RAM,
#      and Node.js/npm builds will OOM without swap)
#   2. Updates system packages
#   3. Installs Docker Engine and Docker Compose plugin
#   4. Waits for Terraform's file provisioner to upload docker-compose.yml
#      and src/ to /home/ubuntu/thermos
#   5. Builds and starts all containers with docker compose
#   6. Runs health checks and prints the final URLs
#
# HOW LONG: 3–5 minutes on a t3.medium (most time is spent on docker compose build).
#
# LOG LOCATION: /var/tmp/thermos-setup.log
# =============================================================================

set -euxo pipefail

LOGFILE="/var/tmp/thermos-setup.log"
exec 1>>"$LOGFILE" 2>&1

echo "=========================================="
echo "Thermos Setup Started: $(date)"
echo "=========================================="

# =============================================================================
# Step 0: Add swap space (CRITICAL for t3.medium)
# =============================================================================
echo "[0/7] Adding swap space..."
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "[0/7] Swap added (2 GB)"
else
  echo "[0/7] Swap already exists"
fi

# =============================================================================
# Step 1: Update system packages
# =============================================================================
echo "[1/7] Updating system packages..."
apt-get update -y
apt-get install -y ca-certificates curl git wget jq

# =============================================================================
# Step 2: Install Docker
# =============================================================================
echo "[2/7] Installing Docker..."

# Add Docker GPG key with retry
for i in {1..3}; do
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && break
  echo "Docker GPG key download failed, retrying ($i/3)..."
  sleep 5
done
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker service
systemctl enable docker
systemctl start docker

echo "[2/7] Docker installed successfully"

# =============================================================================
# Step 3: Configure Docker for ubuntu user
# =============================================================================
echo "[3/7] Configuring Docker permissions..."
usermod -aG docker ubuntu
mkdir -p /home/ubuntu/.docker
chown ubuntu:ubuntu /home/ubuntu/.docker
echo "[3/7] Docker permissions configured"

# =============================================================================
# Step 4: Wait for application files (uploaded by Terraform's file provisioner)
# =============================================================================
echo "[4/7] Waiting for application files to arrive..."

APP_DIR="/home/ubuntu/thermos"
MAX_WAIT_SECONDS=600
WAITED=0

while [ ! -f "${APP_DIR}/docker-compose.yml" ] || [ ! -d "${APP_DIR}/src" ]; do
  if [ "$WAITED" -ge "$MAX_WAIT_SECONDS" ]; then
    echo "ERROR: Application files did not arrive within ${MAX_WAIT_SECONDS}s"
    echo "Current contents of ${APP_DIR}:"
    ls -la "${APP_DIR}" 2>/dev/null || echo "(directory does not exist yet)"
    echo ""
    echo "This usually means Terraform's 'file' provisioner failed or was"
    echo "interrupted. Re-run ./scripts/03-deploy.sh to retry."
    exit 1
  fi
  sleep 5
  WAITED=$((WAITED + 5))
done

chown -R ubuntu:ubuntu "${APP_DIR}"
cd "${APP_DIR}"

echo "[4/7] Application files found after ${WAITED}s"

# =============================================================================
# Step 5: Build and start Docker Compose services
# =============================================================================
echo "[5/7] Building and starting Docker Compose services..."

# Clean up old builds to free disk space
docker system prune -af --volumes >/dev/null 2>&1 || true

# Build images (this is the slow part on t3.medium — be patient)
echo "[5/7] Building images (this may take 3–5 minutes on t3.medium)..."
sudo -u ubuntu docker compose build --no-cache

echo "[5/7] Starting containers..."
sudo -u ubuntu docker compose up -d

echo "[5/7] Containers started. Waiting 60s for initialization..."
sleep 60

# =============================================================================
# Step 6: Verify containers are running
# =============================================================================
echo "[6/7] Verifying containers..."
for service in thermos-postgres thermos-backend thermos-frontend; do
  if docker compose ps | grep -q "$service.*Up"; then
    echo "✓ $service is running"
  else
    echo "✗ $service is NOT running"
    echo "Logs for $service:"
    docker compose logs --tail=30 "$service" || true
  fi
done

# =============================================================================
# Step 7: Final health checks
# =============================================================================
echo "[7/7] Running final health checks..."

# Get public IP using IMDSv2 (required because main.tf sets http_tokens = required)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 || echo "unknown")

# Check backend health
BACKEND_OK=0
for i in {1..12}; do
  if curl -sf http://localhost:5000/health >/dev/null 2>&1; then
    echo "✓ Backend is healthy"
    BACKEND_OK=1
    break
  fi
  echo "  Backend not ready yet (attempt $i/12)..."
  sleep 10
done

# Check frontend
FRONTEND_OK=0
for i in {1..12}; do
  if curl -sf http://localhost/ >/dev/null 2>&1; then
    echo "✓ Frontend is responding"
    FRONTEND_OK=1
    break
  fi
  echo "  Frontend not ready yet (attempt $i/12)..."
  sleep 10
done

echo ""
echo "=========================================="
echo "Thermos Setup Complete: $(date)"
if [ "$BACKEND_OK" -eq 1 ] && [ "$FRONTEND_OK" -eq 1 ]; then
  echo "✅ ALL SERVICES HEALTHY"
else
  echo "⚠️  SOME SERVICES NOT RESPONDING"
  echo "Check logs: cat /var/tmp/thermos-setup.log"
fi
echo "Frontend: http://${PUBLIC_IP}"
echo "API:      http://${PUBLIC_IP}:5000/api"
echo "Logs:     tail -f /var/tmp/thermos-setup.log"
echo "=========================================="
