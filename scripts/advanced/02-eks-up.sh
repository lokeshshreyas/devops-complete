#!/usr/bin/env bash
# =============================================================================
# eks-up.sh - OPTIONAL "Level 2": create the EKS cluster + ECR repos
#             (terraform-eks/) that scripts/advanced/03-k8s-deploy.sh deploys onto.
#
# This is a separate, optional path from the core workshop (RUNBOOK.md).
# EKS costs money for every hour the control plane exists - see
# docs/11-kubernetes-eks-optional.md before running this.
#
# Usage:
#   ./scripts/advanced/02-eks-up.sh                          # asks for node instance type
#   ./scripts/advanced/02-eks-up.sh --node-instance-type=t3.micro
#
# Allowed node instance types: t3.micro, t3.medium (see terraform-eks/variables.tf
# for why t3.medium is the default - t3.micro's pod-slot limit is too small to
# schedule the app once system daemonsets are accounted for).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
EKS_DIR="${PROJECT_ROOT}/terraform-eks"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }

print_header "Thermos Level 2: Creating EKS cluster    10 - 15 mins approximately"

command -v terraform >/dev/null 2>&1 || { echo "terraform not found - run ./scripts/01-setup.sh first"; exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { echo "AWS credentials not configured - run 'aws configure' first"; exit 1; }

# =============================================================================
# Node instance type selection
# =============================================================================
NODE_INSTANCE_TYPE=""
for arg in "$@"; do
  case "$arg" in
    --node-instance-type=*) NODE_INSTANCE_TYPE="${arg#--node-instance-type=}" ;;
  esac
done

# Must stay in sync with terraform-eks/variables.tf's validation block.
ALLOWED_NODE_INSTANCE_TYPES=(t3.micro t3.medium)
DEFAULT_NODE_INSTANCE_TYPE="t3.medium"

is_allowed_node_type() {
  local candidate="$1"
  for t in "${ALLOWED_NODE_INSTANCE_TYPES[@]}"; do
    [ "$candidate" = "$t" ] && return 0
  done
  return 1
}

if [ -n "$NODE_INSTANCE_TYPE" ]; then
  if ! is_allowed_node_type "$NODE_INSTANCE_TYPE"; then
    echo "Invalid --node-instance-type '$NODE_INSTANCE_TYPE'. Allowed: ${ALLOWED_NODE_INSTANCE_TYPES[*]}"
    exit 1
  fi
  print_info "Using node instance type from --node-instance-type: $NODE_INSTANCE_TYPE"
else
  echo ""
  print_info "Allowed EKS node instance types: ${ALLOWED_NODE_INSTANCE_TYPES[*]}"
  print_info "Recommended: t3.medium (default). t3.micro's pod-slot limit is fully consumed"
  print_info "by system daemonsets, leaving no room to schedule the app - see"
  print_info "terraform-eks/variables.tf and docs/03-kodekloud-aws-playground-limits.md."
  while true; do
    read -r -p "Enter EKS node instance type [${DEFAULT_NODE_INSTANCE_TYPE}]: " NODE_TYPE_INPUT
    NODE_INSTANCE_TYPE="${NODE_TYPE_INPUT:-$DEFAULT_NODE_INSTANCE_TYPE}"
    if is_allowed_node_type "$NODE_INSTANCE_TYPE"; then
      break
    fi
    echo "'$NODE_INSTANCE_TYPE' isn't allowed. Choose one of: ${ALLOWED_NODE_INSTANCE_TYPES[*]}"
  done
  print_success "Using node instance type: $NODE_INSTANCE_TYPE"
fi

print_info "EKS control plane billing starts as soon as this finishes and runs until"
print_info "you destroy it with ./scripts/advanced/04-k8s-destroy.sh - even if you're not using it."
read -r -p "Continue creating the EKS cluster? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
  print_info "Cancelled."
  exit 0
fi

cd "$EKS_DIR"

print_header "Ensuring required IAM roles exist (KodeKloud-compatible names)    10 - 20 secs approximately"
print_info "The KodeKloud AWS Playground scopes EKS IAM permissions around two exact"
print_info "role names: eksClusterRole and AmazonEKSNodeRole. This step reuses them"
print_info "if they already exist in your account, or creates them if not."

ensure_iam_role() {
  local role_name="$1"
  local trust_policy="$2"
  shift 2
  local policies=("$@")

  if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    print_info "IAM role '$role_name' already exists - reusing it"
  else
    print_info "Creating IAM role '$role_name'..."
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "$trust_policy" >/dev/null
    for policy_arn in "${policies[@]}"; do
      aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
    done
    print_success "Created '$role_name' and attached its policies"
    print_info "Waiting 10s for IAM role propagation..."
    sleep 10
  fi
}

CLUSTER_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
NODE_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

ensure_iam_role "eksClusterRole" "$CLUSTER_TRUST" \
  "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

ensure_iam_role "AmazonEKSNodeRole" "$NODE_TRUST" \
  "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" \
  "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
  "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"

print_header "Creating EKS cluster    10 - 15 mins approximately"
terraform init -input=false
terraform apply -auto-approve -input=false -var="node_instance_type=${NODE_INSTANCE_TYPE}"

print_header "EKS cluster created"
print_success "Cluster: $(terraform output -raw cluster_name)"
print_info "Next: ./scripts/advanced/03-k8s-deploy.sh"
print_info "When done: ./scripts/advanced/04-k8s-destroy.sh (do this before your KodeKloud session ends!)"
