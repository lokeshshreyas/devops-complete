#!/usr/bin/env bash
# =============================================================================
# 05-destroy-backend.sh - OPTIONAL: tear down the remote state S3 bucket +
#                          DynamoDB lock table created by 01-setup-backend.sh
#
# IMPORTANT ORDER: run this LAST, after:
#   ./scripts/07-destroy.sh              (destroys the main EC2/VPC infra)
#   ./scripts/advanced/04-k8s-destroy.sh (if you ever used EKS - destroys it too)
# Both modules' state files live inside this bucket, so destroying the bucket
# first would strand them.
#
# Usage: ./scripts/advanced/05-destroy-backend.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKEND_DIR="${PROJECT_ROOT}/terraform-docker/backend"
DOCKER_DIR="${PROJECT_ROOT}/terraform-docker"
EKS_DIR="${PROJECT_ROOT}/terraform-eks"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }

print_header "Destroying remote Terraform state (S3 + DynamoDB)    < 1 min approximately"

is_backend_active() {
  local backend_file="$1"
  [ -f "$backend_file" ] && grep -qE '^\s*backend\s+"s3"\s*\{' "$backend_file"
}

DOCKER_ACTIVE=0; is_backend_active "${DOCKER_DIR}/backend.tf" && DOCKER_ACTIVE=1
EKS_ACTIVE=0;    is_backend_active "${EKS_DIR}/backend.tf"    && EKS_ACTIVE=1

if [ "$DOCKER_ACTIVE" -eq 0 ] && [ "$EKS_ACTIVE" -eq 0 ] && [ ! -f "${BACKEND_DIR}/terraform.tfstate" ]; then
  print_info "No remote state backend found - nothing to do."
  exit 0
fi

print_warning "Make sure you've already destroyed the infrastructure that used this backend:"
print_warning "  - ./scripts/07-destroy.sh              (Level 1: EC2/VPC - always applies)"
print_warning "  - ./scripts/advanced/04-k8s-destroy.sh  (Level 2: only if you ever ran 02-eks-up.sh)"
read -r -p "Have you already destroyed all of the above? (yes/no): " confirmed

if [ "$confirmed" != "yes" ]; then
  print_info "Aborting. Run the destroy scripts above first, then re-run this script."
  exit 0
fi

cd "$BACKEND_DIR"

if [ -f "terraform.tfstate" ]; then
  print_info "Running terraform destroy in terraform-docker/backend/ ..."
  print_info "(the bucket has force_destroy=true, so Terraform empties it automatically)"
  terraform destroy -auto-approve -input=false || print_error "Backend destroy had issues - check the AWS Console for leftover S3/DynamoDB resources"
else
  print_info "No local backend/ state found - skipping terraform destroy (bucket may already be gone)"
fi

restore_template() {
  local module_dir="$1"
  local module_name="$2"
  if [ -f "${module_dir}/backend.tf.template" ]; then
    cp "${module_dir}/backend.tf.template" "${module_dir}/backend.tf"
    print_success "Restored ${module_name}/backend.tf to its inactive template (back to local state)"
  else
    rm -f "${module_dir}/backend.tf"
    print_success "Removed ${module_name}/backend.tf (back to local state; no template found to restore)"
  fi
}

restore_template "$DOCKER_DIR" "terraform-docker"
restore_template "$EKS_DIR" "terraform-eks"

print_header "Remote state backend destroyed"
