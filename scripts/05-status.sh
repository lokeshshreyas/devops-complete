#!/usr/bin/env bash
# =============================================================================
# 05-status.sh — Quick dashboard: what's running locally and in AWS
#
# WHAT THIS DOES:
#   LOCAL:  Shows if any Thermos Docker containers are running on your machine.
#   AWS:    Queries AWS EC2 directly for instances tagged Project=thermos,
#           showing state, public IP, instance type, and launch time.
#   Also shows whether remote Terraform state (S3 backend) is configured.
#
# WHY USE THIS:
#   Fast way to answer "Did I already deploy something?" before your
#   KodeKloud session ends.
#
# HOW LONG: < 1 minute.
#
# USAGE:
#   ./scripts/05-status.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform-docker"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}"; }

print_header "LOCAL Docker Status"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  cd "$PROJECT_ROOT"
  if docker compose ps >/dev/null 2>&1; then
    RUNNING=$(docker compose ps --status running -q 2>/dev/null | wc -l | tr -d ' ')
    if [ "$RUNNING" -gt 0 ]; then
      echo -e "${YELLOW}⚠️  $RUNNING local container(s) running:${NC}"
      docker compose ps
    else
      echo -e "${GREEN}✅ No local containers running (clean)${NC}"
    fi
  else
    echo -e "${GREEN}✅ No local Compose project running${NC}"
  fi
else
  echo -e "${YELLOW}ℹ️  Docker not installed or daemon not running${NC}"
fi

print_header "AWS EC2 Status (queried directly from AWS)"

if ! command -v aws >/dev/null 2>&1; then
  echo -e "${YELLOW}ℹ️  AWS CLI not installed — cannot query AWS${NC}"
elif ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo -e "${YELLOW}ℹ️  AWS credentials not configured — cannot query AWS${NC}"
else
  # Query AWS directly for Thermos-tagged instances
  INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=thermos" \
    --query 'Reservations[*].Instances[*].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,Type:InstanceType,Launch:LaunchTime}' \
    --output table 2>/dev/null)

  if [ -n "$INSTANCES" ] && echo "$INSTANCES" | grep -q "i-"; then
    echo "$INSTANCES"
  else
    echo -e "${GREEN}✅ No EC2 instances tagged 'Project=thermos' found in AWS${NC}"
  fi
fi

print_header "Terraform State"

if [ -f "${TERRAFORM_DIR}/backend.tf" ] && grep -qE '^\s*backend\s+"s3"\s*\{' "${TERRAFORM_DIR}/backend.tf"; then
  echo -e "${YELLOW}ℹ️  Remote state backend configured (S3)${NC}"
else
  echo -e "${GREEN}✅ Using local Terraform state${NC}"
fi

if [ -d "${TERRAFORM_DIR}/.terraform" ]; then
  cd "$TERRAFORM_DIR"
  RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l | tr -d ' ')
  if [ "$RESOURCE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  $RESOURCE_COUNT resource(s) tracked in local state${NC}"
    terraform state list 2>/dev/null | sed 's/^/    - /'
  else
    echo -e "${GREEN}✅ Terraform state is empty${NC}"
  fi
else
  echo -e "${GREEN}✅ Terraform has not been initialized yet${NC}"
fi

print_header "Summary"
echo -e "${YELLOW}If you see running AWS instances above, run ./scripts/07-destroy.sh before your session ends.${NC}"
