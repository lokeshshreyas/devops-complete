#!/usr/bin/env bash
# =============================================================================
# 07-destroy.sh — Tear down ALL Thermos resources
#
# WHAT THIS DOES:
#   1. DESTROYS AWS infrastructure (EC2, VPC, security group, etc.) via
#      terraform destroy in terraform-docker/
#   2. CLEANS local Docker containers/images left over from 02-validate.sh
#   3. REMOVES local Terraform state files (.terraform, .tfstate, etc.)
#
# WHY RUN THIS:
#   KodeKloud sessions expire in 3 hours. Whatever you create costs real AWS
#   capacity. Always destroy before your session ends.
#
# HOW LONG: 2–3 minutes.
#
# FLAGS:
#   --aws-only    Only destroy AWS infrastructure, skip local Docker cleanup
#   --local-only  Only clean up local Docker, skip AWS destroy
#
# USAGE:
#   ./scripts/07-destroy.sh              # full cleanup (recommended)
#   ./scripts/07-destroy.sh --local-only # just clean local Docker
# =============================================================================

set -uo pipefail

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
print_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }

DO_AWS=1
DO_LOCAL=1
for arg in "$@"; do
  case "$arg" in
    --local-only) DO_AWS=0 ;;
    --aws-only)   DO_LOCAL=0 ;;
  esac
done

print_header "Thermos 07-destroy: Full Teardown"

# =============================================================================
# AWS Teardown
# =============================================================================
if [ "$DO_AWS" -eq 1 ]; then
  print_header "Destroying AWS Infrastructure    2–3 mins"

  if [ ! -d "$TERRAFORM_DIR" ]; then
    print_error "Terraform directory not found: $TERRAFORM_DIR"
    exit 1
  fi

  cd "$TERRAFORM_DIR"

  # Check if there's anything to destroy (works with local or remote state)
  INFRA_FOUND=0
  if [ -f "terraform.tfstate" ]; then
    INFRA_FOUND=1
  elif [ -d ".terraform" ]; then
    if terraform state list >/dev/null 2>&1 && [ -n "$(terraform state list 2>/dev/null)" ]; then
      INFRA_FOUND=1
    fi
  fi

  if [ "$INFRA_FOUND" -eq 0 ]; then
    print_info "No Terraform-managed infrastructure found to destroy"
  else
    print_warn "This will DESTROY all AWS resources created by this project:"
    print_info "  - EC2 Instance"
    print_info "  - VPC, Subnet, Internet Gateway"
    print_info "  - Security Group"
    print_info "  - SSH Key Pair"
    echo ""
    read -p "Type 'yes' to confirm destruction: " confirm
    if [ "$confirm" != "yes" ]; then
      print_info "AWS teardown cancelled"
    else
      print_info "Running: terraform destroy -auto-approve"
      if terraform destroy -auto-approve -no-color; then
        print_success "AWS infrastructure destroyed"
      else
        print_error "Terraform destroy had issues. Check the AWS Console for leftovers."
      fi
    fi
  fi

  # Clean local state files regardless
  print_header "Cleaning Local State Files"
  rm -f "$TERRAFORM_DIR/terraform.tfstate"
  rm -f "$TERRAFORM_DIR/terraform.tfstate.backup"
  rm -f "$TERRAFORM_DIR/.terraform.lock.hcl"
  rm -rf "$TERRAFORM_DIR/.terraform"
  print_success "Local state files removed"

  # Active-stack marker (read by the optional CD workflow — see docs/16)
  if [ -f "${PROJECT_ROOT}/.thermos/active-stack" ] && [ "$(cat "${PROJECT_ROOT}/.thermos/active-stack" 2>/dev/null)" = "docker" ]; then
    echo "none" > "${PROJECT_ROOT}/.thermos/active-stack"
  fi
else
  print_info "Skipping AWS teardown (--local-only passed)"
fi

# =============================================================================
# Local Docker Cleanup
# =============================================================================
if [ "$DO_LOCAL" -eq 1 ]; then
  print_header "Cleaning Local Docker Resources    < 1 min"
  cd "$PROJECT_ROOT"

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker compose ps -q >/dev/null 2>&1 && [ -n "$(docker compose ps -q 2>/dev/null)" ]; then
      print_info "Stopping local Thermos containers"
      docker compose down --remove-orphans
      print_success "Local containers stopped"
    else
      print_success "No local Thermos containers were running"
    fi

    print_info "Removing dangling images and build cache"
    docker image prune -f >/dev/null 2>&1 || true
    docker builder prune -f >/dev/null 2>&1 || true
    print_success "Local Docker cleanup complete"
  else
    print_info "Docker not installed or not running — nothing to clean up locally"
  fi
else
  print_info "Skipping local Docker cleanup (--aws-only passed)"
fi

# =============================================================================
# Final Summary
# =============================================================================
print_header "Teardown Complete"
print_success "✓ AWS infrastructure destroyed (or was not present)"
print_success "✓ Local Docker resources cleaned"
print_success "✓ Local Terraform state cleaned"
print_info ""
print_info "If you had remote state configured (terraform-docker/backend.tf),"
print_info "tear that down too with: ./scripts/advanced/05-destroy-backend.sh"
