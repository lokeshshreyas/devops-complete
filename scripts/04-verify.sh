#!/usr/bin/env bash
# =============================================================================
# 04-verify.sh — Poll the deployed Thermos app until it responds
#
# WHAT THIS DOES:
#   Reads the EC2 public IP from Terraform outputs and repeatedly checks:
#     - Frontend: http://<EC2_IP>/  (should return HTML)
#     - Backend:  http://<EC2_IP>:5000/health  (should return JSON)
#   It retries with a delay between attempts until both respond or the max
#   attempts are exhausted.
#
# WHY THIS MATTERS:
#   After `terraform apply` finishes, the EC2 instance still needs 3–5 minutes
#   to install Docker, build images, and start containers. This script waits
#   for you so you don't have to manually curl repeatedly.
#
# HOW LONG: Up to 10 minutes by default (40 attempts x 15 seconds).
#   On a t3.medium, expect 3–5 minutes. If it takes longer, SSH in and check
#   /var/tmp/thermos-setup.log for errors.
#
# USAGE:
#   ./scripts/04-verify.sh              # default: 40 attempts, 15s delay
#   ./scripts/04-verify.sh 20 10          # 20 attempts, 10s delay
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform-docker"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }
print_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Default: 40 attempts x 15 seconds = 600 seconds = 10 minutes
MAX_ATTEMPTS="${1:-40}"
DELAY_SECONDS="${2:-15}"

print_header "Thermos 04-verify: Deployment Verification"

if [ ! -d "$TERRAFORM_DIR" ]; then
  print_error "Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi

cd "$TERRAFORM_DIR"

EC2_IP="$(terraform output -raw ec2_public_ip 2>/dev/null || true)"
if [ -z "$EC2_IP" ]; then
  print_error "Could not read ec2_public_ip from Terraform output."
  print_info "Run ./scripts/03-deploy.sh first."
  exit 1
fi

print_info "Target instance: $EC2_IP"
print_info "Frontend: http://${EC2_IP}/"
print_info "Backend health: http://${EC2_IP}:5000/health"
print_info "Max wait time: $((MAX_ATTEMPTS * DELAY_SECONDS / 60)) minutes ($MAX_ATTEMPTS attempts x ${DELAY_SECONDS}s)"
echo ""

check_endpoint() {
  local url="$1"
  curl --silent --fail --max-time 5 "$url" >/dev/null 2>&1
}

FRONTEND_OK=0
BACKEND_OK=0

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo -n "Attempt ${attempt}/${MAX_ATTEMPTS}: "

  if [ "$FRONTEND_OK" -eq 0 ] && check_endpoint "http://${EC2_IP}/"; then
    FRONTEND_OK=1
  fi

  if [ "$BACKEND_OK" -eq 0 ] && check_endpoint "http://${EC2_IP}:5000/health"; then
    BACKEND_OK=1
  fi

  if [ "$FRONTEND_OK" -eq 1 ] && [ "$BACKEND_OK" -eq 1 ]; then
    echo "BOTH RESPONDING 🎉"
    break
  fi

  echo "frontend=$([ "$FRONTEND_OK" -eq 1 ] && echo OK || echo waiting), backend=$([ "$BACKEND_OK" -eq 1 ] && echo OK || echo waiting)"
  sleep "$DELAY_SECONDS"
done

echo ""
if [ "$FRONTEND_OK" -eq 1 ]; then
  print_success "Frontend is responding: http://${EC2_IP}/"
else
  print_error "Frontend did not respond after $((MAX_ATTEMPTS * DELAY_SECONDS))s"
fi

if [ "$BACKEND_OK" -eq 1 ]; then
  print_success "Backend health check passed: http://${EC2_IP}:5000/health"
else
  print_error "Backend did not respond after $((MAX_ATTEMPTS * DELAY_SECONDS))s"
fi

if [ "$FRONTEND_OK" -eq 1 ] && [ "$BACKEND_OK" -eq 1 ]; then
  echo ""
  print_success "Deployment verified! Open http://${EC2_IP}/ in your browser."
  exit 0
else
  echo ""
  print_warn "Services are not fully up yet. This is normal on t3.medium — builds are slow."
  print_info "To investigate, SSH into the instance:"
  print_info "  ./scripts/06-ssh.sh"
  print_info "  cat /var/tmp/thermos-setup.log          # full boot log"
  print_info "  docker compose ps                       # container status"
  print_info "  docker compose logs -f                  # live logs"
  print_info ""
  print_info "Common causes:"
  print_info "  • Docker build still running (t3.medium is slow — wait longer)"
  print_info "  • Out of memory during build (check dmesg | tail -20)"
  print_info "  • File provisioner didn't complete (re-run ./scripts/03-deploy.sh)"
  exit 1
fi
