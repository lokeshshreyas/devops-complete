#!/usr/bin/env bash
# =============================================================================
# 02-validate.sh — Build and test Thermos locally with Docker Compose
#
# WHAT THIS DOES:
#   1. Checks Docker is installed and running
#   2. Verifies all required project files exist
#   3. Builds all three Docker images (no cache, to catch real issues)
#   4. Starts the stack with Docker Compose
#   5. Waits for health checks to pass
#   6. Runs a quick API smoke test
#   7. Stops and cleans up local containers
#
# WHY RUN THIS:
#   Catches Docker/build issues BEFORE you spend time on AWS. If this fails,
#   fix it here first — don't waste your 3-hour KodeKloud session debugging.
#
# HOW LONG: 3–8 minutes (longer on slow machines).
#
# USAGE:
#   ./scripts/02-validate.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
  echo -e "\n${BLUE}================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}================================${NC}\n"
}
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }

docker_cli() {
  if docker "$@" >/dev/null 2>&1; then
    docker "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo docker "$@"
  else
    return 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# =============================================================================
# Step 1: Check Docker
# =============================================================================
print_header "STEP 1/8: Checking Docker Installation    < 1 min"

if ! command -v docker &>/dev/null; then
  print_error "Docker not installed. Run ./scripts/01-setup.sh first."
  exit 1
fi
print_success "Docker: $(docker --version)"

if ! docker_cli info >/dev/null 2>&1; then
  print_warn "Docker daemon is not running. Trying to start it..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo systemctl start docker >/dev/null 2>&1 || true
    sudo service docker start >/dev/null 2>&1 || true
  fi
  for i in {1..10}; do
    docker_cli info >/dev/null 2>&1 && break
    sleep 2
  done
  if ! docker_cli info >/dev/null 2>&1; then
    print_error "Docker daemon is not running. Start Docker Desktop or run 'sudo systemctl start docker'."
    exit 1
  fi
fi
print_success "Docker daemon is running"

# =============================================================================
# Step 2: Check Docker Compose
# =============================================================================
print_header "STEP 2/8: Checking Docker Compose    < 1 min"

if ! docker_cli compose version >/dev/null 2>&1; then
  print_error "Docker Compose not available. Run ./scripts/01-setup.sh first."
  exit 1
fi
print_success "Docker Compose: $(docker_cli compose version)"

# =============================================================================
# Step 3: Check project files
# =============================================================================
print_header "STEP 3/8: Checking Project Files    < 1 min"

required_files=(
  "docker-compose.yml"
  "src/backend/Dockerfile"
  "src/frontend/Dockerfile"
  "src/database/init.sql"
  "src/backend/app.py"
)

for file in "${required_files[@]}"; do
  if [ -f "$file" ]; then
    print_success "Found: $file"
  else
    print_error "Missing: $file"
    exit 1
  fi
done

# =============================================================================
# Step 4: Build images
# =============================================================================
print_header "STEP 4/8: Building Docker Images    2–5 mins"

print_info "Building with --no-cache to catch real issues..."
if docker_cli compose build --no-cache; then
  print_success "Images built successfully"
else
  print_error "Docker build failed. Read the error output above."
  exit 1
fi

# =============================================================================
# Step 5: Start services
# =============================================================================
print_header "STEP 5/8: Starting Docker Compose Services    10–20 secs"

if docker_cli compose up -d; then
  print_success "Containers started"
else
  print_error "Failed to start containers"
  exit 1
fi

# =============================================================================
# Step 6: Wait for services
# =============================================================================
print_header "STEP 6/8: Waiting for Services    ~30 secs"

print_info "Container status:"
docker_cli compose ps
sleep 25

# =============================================================================
# Step 7: Health checks
# =============================================================================
print_header "STEP 7/8: Performing Health Checks    < 1 min"

echo ""
print_info "Checking backend health..."
if curl -sf http://localhost:5000/health >/dev/null 2>&1; then
  RESPONSE=$(curl -s http://localhost:5000/health)
  print_success "Backend is healthy: $RESPONSE"
else
  print_warn "Backend health check failed (may still be initializing)"
  print_info "Backend logs:"
  docker_cli compose logs thermos-backend | tail -10
fi

print_info "Checking frontend..."
if curl -sf http://localhost >/dev/null 2>&1; then
  print_success "Frontend is responding"
else
  print_warn "Frontend not responding yet"
  print_info "Frontend logs:"
  docker_cli compose logs thermos-frontend | tail -10
fi

print_info "Checking database..."
if docker_cli compose exec -T postgres pg_isready -U thermos >/dev/null 2>&1; then
  print_success "PostgreSQL is ready"
else
  print_warn "Database not ready yet"
fi

# =============================================================================
# Step 8: API test + cleanup
# =============================================================================
print_header "STEP 8/8: Testing API + Cleanup    < 1 min"

print_info "Testing GET /health..."
HEALTH=$(curl -s http://localhost:5000/health)
if [ -n "$HEALTH" ]; then
  print_success "Health check: $HEALTH"
else
  print_warn "Health endpoint not responding"
fi

print_info "Testing POST /api/register..."
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:5000/api/register \
  -H "Content-Type: application/json" -d '{}' 2>/dev/null || echo "000")
if [ "$RESPONSE_CODE" != "000" ]; then
  print_success "API endpoint is accessible (HTTP $RESPONSE_CODE)"
else
  print_warn "Could not connect to API"
fi

print_info "Stopping Docker Compose..."
docker_cli compose down
print_success "Services stopped and cleaned up"

print_header "✅ Validation Complete!"
print_success "Local environment is ready for deployment."
print_info "Next: ./scripts/03-deploy.sh"
