#!/usr/bin/env bash
# =============================================================================
# 01-setup.sh — Install all prerequisite tools for the Thermos project
#
# WHAT THIS DOES:
#   Detects your OS (Linux or macOS) and installs only the tools you are
#   missing: git, jq, AWS CLI v2, Terraform, Docker (+ Compose plugin), and
#   kubectl (for Level 2). It is safe to re-run — already-installed tools are
#   skipped automatically.
#
# HOW LONG: 0 seconds if everything is installed, up to 5 minutes if not.
#
# USAGE:
#   ./scripts/01-setup.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step()    { echo -e "\n${BLUE}==> $1${NC}"; }
log_ok()      { echo -e "${GREEN}  ✅ $1${NC}"; }
log_skip()    { echo -e "${YELLOW}  ⏭  $1${NC}"; }
log_warn()    { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
log_err()     { echo -e "${RED}  ❌ $1${NC}"; }

START_TIME=$(date +%s)

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE} Thermos 01-setup: installing prerequisites       ${NC}"
echo -e "${BLUE} instant if already installed, up to 5 mins if not ${NC}"
echo -e "${BLUE}================================================${NC}"

OS="unknown"
case "$(uname -s 2>/dev/null || echo unknown)" in
  Linux*)  OS="linux" ;;
  Darwin*) OS="macos" ;;
  *)       OS="unknown" ;;
esac
log_step "Detected OS: $OS"

APT_UPDATED=0
apt_update_once() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    log_step "Refreshing apt package index (once)"
    sudo apt-get update -y -qq
    APT_UPDATED=1
  fi
}

# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------
log_step "Checking git"
if command -v git >/dev/null 2>&1; then
  log_skip "git already installed: $(git --version)"
else
  if [ "$OS" = "linux" ]; then
    apt_update_once
    sudo apt-get install -y -qq git
  elif [ "$OS" = "macos" ]; then
    command -v brew >/dev/null 2>&1 || { log_err "Homebrew not found. Install from https://brew.sh/ first."; exit 1; }
    brew install git
  else
    log_err "Unsupported OS for automatic git install. Install manually: https://git-scm.com/downloads"
    exit 1
  fi
  log_ok "git installed: $(git --version)"
fi

# ---------------------------------------------------------------------------
# jq
# ---------------------------------------------------------------------------
log_step "Checking jq"
if command -v jq >/dev/null 2>&1; then
  log_skip "jq already installed: $(jq --version)"
else
  if [ "$OS" = "linux" ]; then
    apt_update_once
    sudo apt-get install -y -qq jq
  elif [ "$OS" = "macos" ]; then
    brew install jq
  fi
  command -v jq >/dev/null 2>&1 && log_ok "jq installed: $(jq --version)" || log_warn "jq install may have failed (non-critical)"
fi

# ---------------------------------------------------------------------------
# AWS CLI v2
# ---------------------------------------------------------------------------
log_step "Checking AWS CLI"
if command -v aws >/dev/null 2>&1; then
  log_skip "AWS CLI already installed: $(aws --version 2>&1)"
else
  if [ "$OS" = "linux" ]; then
    apt_update_once
    sudo apt-get install -y -qq unzip curl
    TMP_DIR="$(mktemp -d)"
    curl -fsSL --retry 3 --retry-delay 3 "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$TMP_DIR/awscliv2.zip"
    unzip -q "$TMP_DIR/awscliv2.zip" -d "$TMP_DIR"
    sudo "$TMP_DIR/aws/install" --update
    rm -rf "$TMP_DIR"
  elif [ "$OS" = "macos" ]; then
    brew install awscli
  fi
  command -v aws >/dev/null 2>&1 && log_ok "AWS CLI installed: $(aws --version 2>&1)" || { log_err "AWS CLI install failed"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Terraform (>= 1.0)
# ---------------------------------------------------------------------------
log_step "Checking Terraform"
if command -v terraform >/dev/null 2>&1; then
  log_skip "Terraform already installed: $(terraform --version | head -1)"
else
  if [ "$OS" = "linux" ]; then
    apt_update_once
    sudo apt-get install -y -qq gnupg software-properties-common curl lsb-release
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    sudo apt-get update -y -qq
    sudo apt-get install -y -qq terraform
  elif [ "$OS" = "macos" ]; then
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
  fi
  command -v terraform >/dev/null 2>&1 && log_ok "Terraform installed: $(terraform --version | head -1)" || { log_err "Terraform install failed"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Docker + Compose plugin
# ---------------------------------------------------------------------------
log_step "Checking Docker"
if command -v docker >/dev/null 2>&1; then
  log_skip "Docker already installed: $(docker --version)"
else
  if [ "$OS" = "linux" ]; then
    apt_update_once
    sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL --retry 3 --retry-delay 3 https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif [ "$OS" = "macos" ]; then
    log_warn "Docker Desktop can't be fully automated on macOS."
    log_warn "Install from https://www.docker.com/products/docker-desktop and open it."
  fi
  command -v docker >/dev/null 2>&1 && log_ok "Docker installed: $(docker --version)" || log_warn "Docker install may need a manual finish"
fi

if [ "$OS" = "linux" ]; then
  log_step "Ensuring Docker daemon is running and enabled"
  sudo systemctl enable docker >/dev/null 2>&1 || true
  sudo systemctl start docker >/dev/null 2>&1 || true
  if docker info >/dev/null 2>&1 || sudo docker info >/dev/null 2>&1; then
    log_ok "Docker daemon is running"
  else
    log_warn "Docker daemon did not start automatically - check 'sudo systemctl status docker'"
  fi

  if id -nG "$USER" 2>/dev/null | grep -qw docker; then
    log_skip "$USER is already in the docker group"
  else
    log_step "Adding $USER to the docker group (log out/in for it to take effect)"
    sudo usermod -aG docker "$USER"
    log_ok "Added $USER to docker group"
  fi
fi

# ---------------------------------------------------------------------------
# kubectl (Level 2 only — optional)
# ---------------------------------------------------------------------------
log_step "Checking kubectl"
if command -v kubectl >/dev/null 2>&1; then
  log_skip "kubectl already installed: $(kubectl version --client 2>&1 | head -1)"
else
  if [ "$OS" = "linux" ]; then
    apt_update_once
    sudo apt-get install -y -qq curl ca-certificates
    KUBECTL_VERSION="$(curl -fsSL --retry 3 --retry-delay 3 https://dl.k8s.io/release/stable.txt)"
    curl -fsSL --retry 3 --retry-delay 3 \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /tmp/kubectl
    sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
  elif [ "$OS" = "macos" ]; then
    brew install kubectl
  else
    log_err "Unsupported OS for automatic kubectl install. Install manually: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi
  command -v kubectl >/dev/null 2>&1 && log_ok "kubectl installed: $(kubectl version --client 2>&1 | head -1)" || { log_err "kubectl install failed"; exit 1; }
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
ELAPSED=$(( $(date +%s) - START_TIME ))

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE} Setup summary (${ELAPSED}s)                    ${NC}"
echo -e "${BLUE}================================================${NC}"
command -v git       >/dev/null 2>&1 && log_ok "git: $(git --version)"             || log_err "git missing"
command -v terraform >/dev/null 2>&1 && log_ok "terraform: $(terraform --version | head -1)" || log_err "terraform missing"
command -v aws       >/dev/null 2>&1 && log_ok "aws cli: $(aws --version 2>&1)"    || log_err "aws cli missing"
command -v docker    >/dev/null 2>&1 && log_ok "docker: $(docker --version)"       || log_err "docker missing"
command -v jq        >/dev/null 2>&1 && log_ok "jq: $(jq --version)"               || log_warn "jq missing (non-critical)"
command -v kubectl   >/dev/null 2>&1 && log_ok "kubectl: $(kubectl version --client 2>&1 | head -1)" || log_warn "kubectl missing (only needed for Level 2 / EKS)"

echo ""
echo "Next steps:"
echo "  1. aws configure                 # paste your KodeKloud AWS Playground credentials"
echo "  2. ./scripts/02-validate.sh      # optional: test the app locally first"
echo "  3. ./scripts/03-deploy.sh        # deploy to AWS"
echo ""
if [ "$OS" = "linux" ] && ! id -nG "$USER" 2>/dev/null | grep -qw docker; then
  log_warn "You may need to log out and back in before running 'docker' without sudo."
fi
