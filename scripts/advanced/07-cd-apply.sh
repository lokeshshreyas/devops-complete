#!/usr/bin/env bash
# =============================================================================
# 07-cd-apply.sh - Non-interactive apply used by .github/workflows/cd.yml
#
# This is the ONLY script in the project that assumes it might be running
# unattended (in CI) rather than in front of a person - so it never prompts,
# and it fails LOUDLY with a specific, actionable message instead of hanging.
#
# What it does:
#   1. Reads .thermos/active-stack ("docker", "eks", or "none")
#   2. If "docker": terraform apply in terraform-docker/ (updates the EC2/VPC
#      infra to match whatever changed in that directory)
#   3. If "eks": terraform apply in terraform-eks/ (infra), then rebuilds and
#      pushes the app images and re-applies kubernetes/*.yaml (app changes) -
#      the same two things scripts/advanced/03-k8s-deploy.sh does, just
#      non-interactively
#   4. If "none": exits 0 immediately - nothing is deployed, so there's
#      nothing to update
#
# You can also run this by hand to see exactly what CD would do:
#   ./scripts/advanced/07-cd-apply.sh
#
# Usage: ./scripts/advanced/07-cd-apply.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DOCKER_DIR="${PROJECT_ROOT}/terraform-docker"
EKS_DIR="${PROJECT_ROOT}/terraform-eks"
K8S_DIR="${PROJECT_ROOT}/kubernetes"
MARKER_FILE="${PROJECT_ROOT}/.thermos/active-stack"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header()  { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }

print_header "Thermos CD: Applying changes for the active stack"

# =============================================================================
# Fail fast and clearly if AWS credentials are missing or expired. This is
# the single most likely failure mode for CD on a KodeKloud-based setup: the
# GitHub secret still holds LAST session's temporary credentials.
# =============================================================================
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  print_error "AWS credentials are missing or expired."
  print_info "If this is running in GitHub Actions: the KodeKloud session credentials"
  print_info "stored as repo secrets have expired (they only last one ~3 hour session)."
  print_info "Fix: start a new KodeKloud session, then re-run"
  print_info "  ./scripts/advanced/06-setup-cicd.sh"
  print_info "locally to refresh the AWS_* secrets, then push again."
  exit 1
fi

if [ ! -f "$MARKER_FILE" ]; then
  print_info "No ${MARKER_FILE} found - nothing is marked as deployed. Nothing to do."
  exit 0
fi

ACTIVE_STACK="$(tr -d '[:space:]' < "$MARKER_FILE")"
print_info "Active stack: ${ACTIVE_STACK}"

case "$ACTIVE_STACK" in
  none)
    print_info "No stack is currently deployed (active-stack = none). Nothing to do."
    exit 0
    ;;

  docker)
    print_header "Applying terraform-docker/ (Docker Compose on EC2)"
    cd "$DOCKER_DIR"
    terraform init -input=false
    terraform apply -auto-approve -input=false
    print_success "terraform-docker/ is up to date"
    ;;

  eks)
    print_header "Applying terraform-eks/ (infrastructure)"
    cd "$EKS_DIR"
    terraform init -input=false
    terraform apply -auto-approve -input=false
    print_success "terraform-eks/ infrastructure is up to date"

    CLUSTER_NAME="$(terraform output -raw cluster_name)"
    REGION="$(terraform output -raw configure_kubectl_command | sed -n 's/.*--region \(.*\)/\1/p')"
    ECR_BACKEND="$(terraform output -raw ecr_backend_url)"
    ECR_FRONTEND="$(terraform output -raw ecr_frontend_url)"

    print_header "Rebuilding and pushing application images"
    cd "$PROJECT_ROOT"
    docker build -t thermos-backend:latest -f src/backend/Dockerfile src/backend
    docker build -t thermos-frontend:latest -f src/frontend/Dockerfile src/frontend

    aws ecr get-login-password --region "$REGION" \
      | docker login --username AWS --password-stdin "$(echo "$ECR_BACKEND" | cut -d/ -f1)"
    docker tag thermos-backend:latest "${ECR_BACKEND}:latest"
    docker tag thermos-frontend:latest "${ECR_FRONTEND}:latest"
    docker push "${ECR_BACKEND}:latest"
    docker push "${ECR_FRONTEND}:latest"
    print_success "Images pushed to ECR"

    print_header "Re-applying Kubernetes manifests"
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null
    TMP_DIR="$(mktemp -d)"
    cp "${K8S_DIR}"/*.yaml "$TMP_DIR"/
    sed -i.bak "s|IMAGE_PLACEHOLDER_BACKEND|${ECR_BACKEND}:latest|g" "${TMP_DIR}/02-backend.yaml"
    sed -i.bak "s|IMAGE_PLACEHOLDER_FRONTEND|${ECR_FRONTEND}:latest|g" "${TMP_DIR}/03-frontend.yaml"

    kubectl apply -f "${TMP_DIR}/00-secrets.yaml"
    kubectl apply -f "${TMP_DIR}/01-postgres.yaml"
    kubectl rollout status deployment/postgres --timeout=180s
    kubectl apply -f "${TMP_DIR}/02-backend.yaml"
    kubectl rollout status deployment/thermos-backend --timeout=180s
    kubectl apply -f "${TMP_DIR}/03-frontend.yaml"
    kubectl rollout status deployment/thermos-frontend --timeout=180s
    rm -rf "$TMP_DIR"
    print_success "Kubernetes manifests re-applied and rollouts complete"
    ;;

  *)
    print_error "Unrecognized value in ${MARKER_FILE}: '${ACTIVE_STACK}' (expected docker, eks, or none)"
    exit 1
    ;;
esac

print_header "CD apply complete"
