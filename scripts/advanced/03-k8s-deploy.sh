#!/usr/bin/env bash
# =============================================================================
# k8s-deploy.sh - OPTIONAL "Level 2": deploy Thermos to Kubernetes (EKS)
#
# ⚠️  CRITICAL: This script does NOT create the EKS cluster. You MUST run
#     ./scripts/advanced/02-eks-up.sh FIRST, wait for it to complete (10-15 min),
#     and ONLY THEN run this script.
#
# ⚠️  CRITICAL: After this script prints a URL, the AWS Network Load Balancer
#     needs an ADDITIONAL 3-5 minutes to fully provision before you can
#     access it in a browser. This is normal AWS behavior, not a bug.
#
# What this script does:
#   1. Builds the backend/frontend Docker images
#   2. Pushes them to the ECR repos Terraform created
#   3. Points kubectl at the new cluster
#   4. Waits for at least one worker node to be Ready
#   5. Applies kubernetes/*.yaml with real image URIs substituted in
#   6. Waits for each Deployment rollout to complete
#   7. Waits for the LoadBalancer hostname to be assigned
#   8. Polls the LoadBalancer URL until it actually responds
#
# Total time: ~5-10 minutes for this script, PLUS 3-5 minutes for NLB
# provisioning AFTER the script finishes. Budget 20-30 minutes total
# from ./scripts/advanced/02-eks-up.sh to a working browser URL.
#
# Usage: ./scripts/advanced/03-k8s-deploy.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
EKS_DIR="${PROJECT_ROOT}/terraform-eks"
K8S_DIR="${PROJECT_ROOT}/kubernetes"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }
print_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }

print_header "Thermos Level 2: Deploying to Kubernetes (EKS)"

# =============================================================================
# Pre-flight checks
# =============================================================================
for tool in terraform aws docker kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { print_error "$tool not found. See docs/11-kubernetes-eks-optional.md for what to install."; exit 1; }
done

if [ ! -f "${EKS_DIR}/terraform.tfstate" ]; then
  print_error "EKS cluster not found. You MUST run ./scripts/advanced/02-eks-up.sh FIRST."
  print_info ""
  print_info "Correct order:"
  print_info "  1. ./scripts/advanced/02-eks-up.sh     # Creates cluster (~10-15 min)"
  print_info "  2. ./scripts/advanced/03-k8s-deploy.sh # Deploys app (~5-10 min)"
  print_info ""
  print_info "Only running terraform apply is NOT enough — it creates infrastructure"
  print_info "but does NOT deploy any application pods or LoadBalancer."
  exit 1
fi

cd "$EKS_DIR"
CLUSTER_NAME="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw configure_kubectl_command | sed -n 's/.*--region \(.*\)/\1/p')"
ECR_BACKEND="$(terraform output -raw ecr_backend_url)"
ECR_FRONTEND="$(terraform output -raw ecr_frontend_url)"

print_info "Cluster: $CLUSTER_NAME (region $REGION)"

# =============================================================================
# Step 1: Build images
# =============================================================================
print_header "Step 1/6: Building images    2-5 mins"
cd "$PROJECT_ROOT"
docker build -t thermos-backend:latest -f src/backend/Dockerfile src/backend
docker build -t thermos-frontend:latest -f src/frontend/Dockerfile src/frontend
print_success "Images built"

# =============================================================================
# Step 2: Push to ECR
# =============================================================================
print_header "Step 2/6: Pushing images to ECR    1-3 mins"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$(echo "$ECR_BACKEND" | cut -d/ -f1)"

docker tag thermos-backend:latest "${ECR_BACKEND}:latest"
docker tag thermos-frontend:latest "${ECR_FRONTEND}:latest"
docker push "${ECR_BACKEND}:latest"
docker push "${ECR_FRONTEND}:latest"
print_success "Images pushed to ECR"

# =============================================================================
# Step 3: Configure kubectl
# =============================================================================
print_header "Step 3/6: Configuring kubectl    < 1 min"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
print_success "kubectl now points at $CLUSTER_NAME"

# =============================================================================
# Step 4: Wait for nodes
# =============================================================================
print_header "Step 4/6: Waiting for at least one node to be Ready    up to 5 mins"
print_info "Self-managed nodes take a few minutes to boot and join the cluster after the"
print_info "ASG launches them - this is normal, not a hang."
NODE_READY=0
for i in $(seq 1 30); do
  if kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -qw "Ready"; then
    NODE_READY=1
    break
  fi
  echo "  waiting for a node to join and become Ready... ($i/30, ~10s each)"
  sleep 10
done

if [ "$NODE_READY" -eq 1 ]; then
  print_success "At least one node is Ready"
  kubectl get nodes
else
  print_error "No node became Ready within 5 minutes - applying manifests now would just hang."
  print_info "Check what's going on with the node before retrying:"
  print_info "  kubectl get nodes"
  print_info "  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${CLUSTER_NAME}-nodes \\"
  print_info "    --query 'AutoScalingGroups[0].Instances[*].InstanceId' --output text"
  print_info "  aws ec2 get-console-output --instance-id <instance-id-from-above> --output text | tail -50"
  print_info "See docs/07-troubleshooting.md for the full node-join troubleshooting entry."
  exit 1
fi

# =============================================================================
# Step 5: Apply manifests
# =============================================================================
wait_for_rollout() {
  local deployment="$1"
  if ! kubectl rollout status "deployment/${deployment}" --timeout=180s; then
    print_error "Rollout of '${deployment}' didn't finish in time. Diagnostics:"
    echo ""
    kubectl get pods -l "app=${deployment}" -o wide || true
    echo ""
    kubectl describe pods -l "app=${deployment}" | tail -40 || true
    echo ""
    print_info "Most recent cluster events:"
    kubectl get events --sort-by=.lastTimestamp | tail -20 || true
    echo ""
    print_info "See docs/07-troubleshooting.md for common causes (ImagePullBackOff, node not Ready, resource limits)."
    exit 1
  fi
}

print_header "Step 5/6: Applying Kubernetes manifests    1-3 mins"
TMP_DIR="$(mktemp -d)"
cp "${K8S_DIR}"/*.yaml "$TMP_DIR"/
sed -i.bak "s|IMAGE_PLACEHOLDER_BACKEND|${ECR_BACKEND}:latest|g" "${TMP_DIR}/02-backend.yaml"
sed -i.bak "s|IMAGE_PLACEHOLDER_FRONTEND|${ECR_FRONTEND}:latest|g" "${TMP_DIR}/03-frontend.yaml"

kubectl apply -f "${TMP_DIR}/00-secrets.yaml"
kubectl apply -f "${TMP_DIR}/01-postgres.yaml"
wait_for_rollout postgres
kubectl apply -f "${TMP_DIR}/02-backend.yaml"
wait_for_rollout thermos-backend
kubectl apply -f "${TMP_DIR}/03-frontend.yaml"
wait_for_rollout thermos-frontend

rm -rf "$TMP_DIR"

print_success "All manifests applied and rollouts complete"

# =============================================================================
# Active-stack marker (read by the optional CD workflow — see docs/16)
# =============================================================================
mkdir -p "${PROJECT_ROOT}/.thermos"
echo "eks" > "${PROJECT_ROOT}/.thermos/active-stack"

# =============================================================================
# Step 6: Wait for LoadBalancer and verify accessibility
# =============================================================================
print_header "Step 6/6: Waiting for LoadBalancer to be accessible    3-8 mins"
print_warn "This is the step most people get impatient with. Read carefully:"
print_info ""
print_info "1. Kubernetes creates the LoadBalancer Service immediately"
print_info "2. AWS provisions the Network Load Balancer (NLB) — this takes 2-3 minutes"
print_info "3. AWS assigns a DNS hostname — this takes another 1-2 minutes"
print_info "4. The NLB starts health-checking pods — 1-2 minutes"
print_info "5. DNS propagates globally — 2-5 minutes"
print_info ""
print_warn "TOTAL after this script: 3-8 more minutes before the URL works in your browser."
print_info "This script will poll the URL for you. Do not cancel."
print_info ""

# First wait for hostname
LB_HOST=""
for i in $(seq 1 30); do
  LB_HOST="$(kubectl get svc thermos-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$LB_HOST" ]; then
    break
  fi
  echo "  [$i/30] Waiting for LoadBalancer hostname..."
  sleep 10
done

if [ -z "$LB_HOST" ]; then
  print_error "LoadBalancer hostname never appeared after 5 minutes."
  print_info "Check: kubectl get svc thermos-frontend"
  print_info "Check: kubectl describe svc thermos-frontend"
  print_info "Common cause: subnet tags missing or incorrect (see docs/12-eks-architecture-and-networking.md)"
  exit 1
fi

print_success "LoadBalancer hostname assigned: $LB_HOST"
print_info "Now polling until the URL actually responds (this is the slow part)..."

# Now poll until it actually responds
URL="http://${LB_HOST}/"
RESPONDING=0
for i in $(seq 1 60); do
  if curl --silent --fail --max-time 5 "$URL" >/dev/null 2>&1; then
    RESPONDING=1
    break
  fi
  echo "  [$i/60] LoadBalancer hostname exists but not responding yet... (normal, NLB still provisioning)"
  sleep 10
done

print_header "Deployment Status"

if [ "$RESPONDING" -eq 1 ]; then
  print_success "🎉 APPLICATION IS ACCESSIBLE!"
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  🌐 Application URL:  ${GREEN}http://${LB_HOST}/${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  print_info "If the URL doesn't work in your browser immediately, wait 1-2 more minutes"
  print_info "for DNS to propagate to your local resolver, then refresh."
else
  print_warn "LoadBalancer hostname assigned but URL not responding after 10 minutes."
  print_info "This can happen if:"
  print_info "  • Pods are still starting (check: kubectl get pods)"
  print_info "  • NLB health checks are failing (check: kubectl describe svc thermos-frontend)"
  print_info "  • Subnet tags are incorrect (see docs/12-eks-architecture-and-networking.md)"
  print_info ""
  print_info "Try these debugging commands:"
  print_info "  kubectl get pods"
  print_info "  kubectl get svc thermos-frontend"
  print_info "  kubectl describe svc thermos-frontend"
  print_info "  kubectl logs -f deploy/thermos-frontend"
  print_info "  curl -v http://${LB_HOST}/"
fi

print_info ""
print_info "Useful commands:"
print_info "  kubectl get pods            # see what's running"
print_info "  kubectl logs -f deploy/thermos-backend   # tail backend logs"
print_info "  kubectl get events --sort-by=.lastTimestamp | tail -20"
print_info ""
print_warn "When done, ALWAYS run: ./scripts/advanced/04-k8s-destroy.sh"
