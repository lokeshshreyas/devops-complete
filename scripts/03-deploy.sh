#!/usr/bin/env bash
# =============================================================================
# 03-deploy.sh — Deploy Thermos to AWS EC2 using Terraform
#
# WHAT THIS DOES:
# 1. Checks that Terraform, AWS CLI, and git are installed
# 2. Verifies your AWS credentials are active
# 3. Asks which EC2 instance type to use (or accepts --instance-type)
# 4. Optionally runs local validation (builds Docker images locally first)
# 5. Runs terraform init → plan → apply
# 6. Prints the EC2 public IP, app URL, and SSH command
#
# HOW LONG: 2–4 minutes for Terraform, plus 3–5 minutes for EC2 boot + Docker build.
#
# FLAGS:
# -y, --yes               Skip the "type yes" confirmation prompt AND the
#                          instance-type prompt (uses the Terraform default,
#                          t3.medium, unless --instance-type is also given)
# --no-verify              Skip the post-deploy verification poll
# --instance-type=TYPE     Use TYPE without prompting, e.g. --instance-type=t3.small
#                          Must be one of: t2.nano, t2.micro, t2.small, t2.medium,
#                          t3.nano, t3.micro, t3.small, t3.medium
#                          (the same set terraform-docker/variables.tf allows)
#
# NOTE: This script does NOT run local validation. Run ./scripts/02-validate.sh
#  BEFORE this script if you want to test locally first.
#
# USAGE:
# ./scripts/03-deploy.sh                          # interactive, asks for instance type
# ./scripts/03-deploy.sh -y                        # auto-confirm everything (fastest path)
# ./scripts/03-deploy.sh --instance-type=t3.small  # skip the prompt, use t3.small
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform-docker"

cd "$PROJECT_ROOT"

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
print_warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }
print_info() { echo -e "${YELLOW}ℹ️ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

AUTO_YES=0
NO_VERIFY=0
INSTANCE_TYPE=""
for arg in "$@"; do
 case "$arg" in
 -y|--yes)  AUTO_YES=1 ;;
 --no-verify) NO_VERIFY=1 ;;
 --instance-type=*) INSTANCE_TYPE="${arg#--instance-type=}" ;;
 esac
done

# =============================================================================
# Allowed instance types — must stay in sync with the validation block in
# terraform-docker/variables.tf (these are the KodeKloud AWS Playground's
# allowed types; anything else will be rejected by 'terraform plan' anyway,
# but we ask here first so freshers get a fast, friendly error instead of a
# Terraform validation error).
# =============================================================================
ALLOWED_INSTANCE_TYPES=(t2.nano t2.micro t2.small t2.medium t3.nano t3.micro t3.small t3.medium)
DEFAULT_INSTANCE_TYPE="t3.medium"

is_allowed_instance_type() {
 local candidate="$1"
 for t in "${ALLOWED_INSTANCE_TYPES[@]}"; do
 [ "$candidate" = "$t" ] && return 0
 done
 return 1
}

print_header "Thermos 03-deploy: AWS Deployment"

# =============================================================================
# Step 1: Prerequisites
# =============================================================================
print_header "STEP 1/4: Prerequisites < 1 min"

for tool in terraform aws git; do
 if ! command -v "$tool" &>/dev/null; then
 print_error "$tool not found. Run ./scripts/01-setup.sh first."
 exit 1
 fi
 print_success "$tool found"
done

if ! aws sts get-caller-identity &>/dev/null; then
 print_error "AWS credentials not configured or expired."
 print_info "Run: aws configure"
 print_info "Use the credentials from your KodeKloud AWS Playground session."
 exit 1
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS credentials OK (account $AWS_ACCOUNT)"

AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
 print_warn "No AWS region configured. Using us-east-1."
 export AWS_DEFAULT_REGION="us-east-1"
else
 print_info "AWS Region: $AWS_REGION"
fi

print_info ""
print_info "Tip: Run ./scripts/02-validate.sh BEFORE this script to catch build issues early."
print_info "It builds all Docker images locally and tests them — much faster than debugging on AWS."

# =============================================================================
# EC2 instance type selection
# =============================================================================
if [ -n "$INSTANCE_TYPE" ]; then
 if ! is_allowed_instance_type "$INSTANCE_TYPE"; then
 print_error "Invalid --instance-type '$INSTANCE_TYPE'."
 print_info "Allowed values: ${ALLOWED_INSTANCE_TYPES[*]}"
 exit 1
 fi
 print_success "Using instance type from --instance-type: $INSTANCE_TYPE"
elif [ "$AUTO_YES" -eq 1 ]; then
 INSTANCE_TYPE="$DEFAULT_INSTANCE_TYPE"
 print_info "Using default instance type: $INSTANCE_TYPE (-y was passed, skipping prompt)"
else
 echo ""
 print_info "Allowed EC2 instance types on the KodeKloud AWS Playground:"
 echo "   ${ALLOWED_INSTANCE_TYPES[*]}"
 print_info "Recommended: t3.medium (default). Smaller types build/run more slowly and"
 print_info "may run out of memory during 'docker compose build' — see docs/07-troubleshooting.md."
 while true; do
 read -r -p "Enter EC2 instance type [${DEFAULT_INSTANCE_TYPE}]: " INSTANCE_TYPE_INPUT
 INSTANCE_TYPE="${INSTANCE_TYPE_INPUT:-$DEFAULT_INSTANCE_TYPE}"
 if is_allowed_instance_type "$INSTANCE_TYPE"; then
 break
 fi
 print_error "'$INSTANCE_TYPE' isn't allowed. Choose one of: ${ALLOWED_INSTANCE_TYPES[*]}"
 done
 print_success "Using instance type: $INSTANCE_TYPE"
fi


# =============================================================================
# Step 2: Terraform init & plan
# =============================================================================
print_header "STEP 2/4: Terraform Init & Plan 1–2 mins"

cd "$TERRAFORM_DIR"

if [ ! -f "main.tf" ] || [ ! -f "user_data.sh" ]; then
 print_error "Missing main.tf or user_data.sh in $TERRAFORM_DIR"
 exit 1
fi

print_info "Running: terraform init"
terraform init -no-color >/dev/null 2>&1 || terraform init
print_success "Terraform initialized"

print_info "Running: terraform plan"
if ! terraform plan -no-color -var="instance_type=${INSTANCE_TYPE}" -out=tfplan >/dev/null 2>&1; then
 print_error "Terraform plan failed"
 terraform plan -var="instance_type=${INSTANCE_TYPE}"
 exit 1
fi
print_success "Terraform plan completed (instance_type=${INSTANCE_TYPE})"

# Show what will be created
print_info "Resources to be created:"
terraform show -no-color tfplan | grep -E '^ \+ ' | head -20 || true

# =============================================================================
# Step 3: Confirmation
# =============================================================================
print_header "STEP 3/4: Confirmation"

echo ""
print_warn "This will create AWS resources in your KodeKloud AWS Playground:"
echo " - 1 VPC (10.0.0.0/16)"
echo " - 1 Public Subnet (10.0.1.0/24)"
echo " - 1 Internet Gateway"
echo " - 1 Security Group"
echo " - 1 EC2 Instance (${INSTANCE_TYPE})"
echo ""
print_warn "Estimated time: 2–4 min for Terraform + 1–2 min for EC2 boot & Docker build."
print_warn "⏰ KodeKloud sessions expire in 3 hours!"
echo ""

if [ "$AUTO_YES" -eq 1 ]; then
 print_info "Auto-confirming (-y passed)"
else
 read -p "Do you want to continue? (type 'yes' to confirm): " confirm
 if [ "$confirm" != "yes" ]; then
 print_warn "Deployment cancelled"
 rm -f tfplan
 exit 0
 fi
fi

# =============================================================================
# Step 4: Apply
# =============================================================================
print_header "STEP 4/4: Creating Infrastructure 2–4 mins"

print_info "Running: terraform apply"
if ! terraform apply -no-color tfplan; then
 print_error "Terraform apply failed"
 rm -f tfplan
 exit 1
fi
rm -f tfplan
print_success "Infrastructure created"

# =============================================================================
# Active-stack marker (read by the optional CD workflow — see docs/16)
# =============================================================================
mkdir -p "${PROJECT_ROOT}/.thermos"
echo "docker" > "${PROJECT_ROOT}/.thermos/active-stack"

# =============================================================================
# Outputs
# =============================================================================
print_header "🎉 Deployment Complete!"

EC2_IP=$(terraform output -raw ec2_public_ip 2>/dev/null || echo "")
APP_URL=$(terraform output -raw app_url 2>/dev/null || echo "")
SSH_CMD=$(terraform output -raw ssh_command 2>/dev/null || echo "")
KEY_PATH=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "")
API_URL=$(terraform output -raw api_url 2>/dev/null || echo "")

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -n "$EC2_IP" ]; then echo -e " 📍 EC2 Instance IP: ${GREEN}${EC2_IP}${NC}"; fi
if [ -n "$APP_URL" ]; then echo -e " 🌐 Application URL: ${GREEN}${APP_URL}${NC}"; fi
if [ -n "$API_URL" ]; then echo -e " 🔌 API URL:   ${GREEN}${API_URL}${NC}"; fi
if [ -n "$SSH_CMD" ]; then echo -e " 🔐 SSH Command:  ${GREEN}${SSH_CMD}${NC}"; fi
if [ -n "$KEY_PATH" ]; then
 echo -e " 🔑 Key File:  ${GREEN}${KEY_PATH}${NC}"
 echo -e "  (Keep this safe. It is required for SSH access.)"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_warn "⏳ The EC2 instance is now booting and installing Docker."
print_warn " On a ${INSTANCE_TYPE} this takes 3–5 minutes (smaller types may take longer). DO NOT CANCEL."
print_info ""
print_info "Next steps:"
print_info " 1. Wait 3–5 minutes"
print_info " 2. Run: ./scripts/04-verify.sh"
print_info " 3. Open the Application URL in your browser"
print_info ""
print_info "To watch progress live:"
print_info " ./scripts/06-ssh.sh"
print_info " cat /var/tmp/thermos-setup.log"
print_info " docker compose logs -f"
print_info ""
print_warn "When done, ALWAYS run: ./scripts/07-destroy.sh"

# =============================================================================
# Optional: auto-verify
# =============================================================================
if [ "$NO_VERIFY" -eq 0 ]; then
 echo ""
 read -p "Wait 30 seconds then auto-run verification? (yes/no): " do_verify
 if [ "$do_verify" = "yes" ]; then
 sleep 30
 "$SCRIPT_DIR/04-verify.sh" || print_warn "Verification will be retried. The instance is still booting."
 fi
fi
