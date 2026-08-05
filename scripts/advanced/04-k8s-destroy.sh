#!/usr/bin/env bash
# =============================================================================
# k8s-destroy.sh - OPTIONAL "Level 2": tear down Kubernetes resources AND the
#                  EKS cluster/ECR repos created by eks-up.sh
#
# Order matters: the LoadBalancer Service must be deleted first so AWS
# releases the associated Elastic Load Balancer before Terraform destroys
# the cluster/VPC underneath it. This script handles that for you.
#
# Usage: ./scripts/k8s-destroy.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
EKS_DIR="${PROJECT_ROOT}/terraform-eks"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }

print_header "Thermos Level 2: Destroying Kubernetes + EKS resources"

if [ ! -f "${EKS_DIR}/terraform.tfstate" ]; then
  print_info "No EKS cluster found (terraform-eks/terraform.tfstate missing) - nothing to do."
  exit 0
fi

cd "$EKS_DIR"
CLUSTER_NAME="$(terraform output -raw cluster_name 2>/dev/null || true)"

if [ -n "$CLUSTER_NAME" ] && command -v kubectl >/dev/null 2>&1; then
  print_info "Deleting the LoadBalancer Service first (releases the AWS ELB)..."

  # Report per-file whether anything actually existed to delete, instead of
  # silently doing nothing for files that were never applied in the first
  # place (e.g. a prior k8s-deploy.sh run that failed partway through) -
  # that distinction matters and previously looked identical either way.
  for f in 03-frontend.yaml 02-backend.yaml 01-postgres.yaml 00-secrets.yaml; do
    OUT="$(kubectl delete -f "${PROJECT_ROOT}/kubernetes/${f}" --ignore-not-found=true 2>&1 || true)"
    if [ -n "$OUT" ]; then
      echo "$OUT"
    else
      print_info "  ${f}: nothing to delete (already gone, or never successfully applied)"
    fi
  done

  print_success "Kubernetes resources deleted (see above for what actually existed)"
  print_info "Waiting 30s for the ELB to fully release before destroying the VPC..."
  sleep 30
else
  print_info "kubectl not available or cluster already gone - skipping k8s cleanup"
fi

print_header "Destroying EKS cluster, worker node ASG, VPC, and ECR repos    8 - 12 mins approximately"
read -p "Type 'yes' to confirm destroying the EKS cluster: " confirm
if [ "$confirm" != "yes" ]; then
  print_info "Cancelled. Kubernetes app resources were already removed above."
  exit 0
fi

if terraform destroy -auto-approve -input=false; then
  print_success "EKS cluster and all related resources destroyed"
else
  print_error "terraform destroy had issues - check the AWS Console (EKS, EC2, VPC, ECR) for leftovers"
fi

# Active-stack marker (read by the optional CD workflow — see docs/16)
if [ -f "${PROJECT_ROOT}/.thermos/active-stack" ] && [ "$(cat "${PROJECT_ROOT}/.thermos/active-stack" 2>/dev/null)" = "eks" ]; then
  echo "none" > "${PROJECT_ROOT}/.thermos/active-stack"
fi

print_header "Level 2 cleanup complete"
