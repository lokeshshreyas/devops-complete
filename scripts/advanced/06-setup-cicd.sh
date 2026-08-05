#!/usr/bin/env bash
# =============================================================================
# 06-setup-cicd.sh - OPTIONAL "Level 2": push this project to YOUR OWN GitHub
#                     repository and wire up the CD (Continuous Deployment)
#                     workflow in .github/workflows/cd.yml
#
# =============================================================================
# WHAT THIS SCRIPT DOES
# =============================================================================
#   1. Initializes a git repo here (if one doesn't already exist), commits
#      everything, and pushes it to a GitHub repository YOU provide.
#   2. Registers your current AWS credentials as encrypted GitHub Actions
#      secrets on that repo, so the CD workflow can use them.
#   3. From then on: every `git push` to `main` that touches `terraform-docker/`,
#      `terraform-eks/`, or `kubernetes/` triggers `.github/workflows/cd.yml`,
#      which runs `scripts/advanced/07-cd-apply.sh` to apply the change to
#      whichever stack is currently active (Docker/EC2, or Kubernetes/EKS) -
#      tracked in `.thermos/active-stack`, written automatically by
#      `03-deploy.sh` and `scripts/advanced/03-k8s-deploy.sh`.
#
# =============================================================================
# ⚠️  READ THIS BEFORE YOU RUN IT — KODEKLOUD CREDENTIAL LIMITATION
# =============================================================================
# The KodeKloud AWS Playground issues SHORT-LIVED, SESSION-SCOPED credentials
# (an access key + secret key + SESSION TOKEN) that stop working the moment
# your ~3-hour lab session ends - often sooner if the session is reset.
#
# This script uploads THOSE credentials as GitHub Actions secrets so the CD
# workflow can use them. That means:
#   - The CD pipeline will WORK for the rest of your current KodeKloud session.
#   - It will START FAILING the moment those credentials expire, with a clear
#     error message from 07-cd-apply.sh (not a silent hang).
#   - You must RE-RUN this script every time you start a new KodeKloud session
#     and want CD to keep working, to refresh the secrets with new credentials.
#
# This is intentional and is exactly the lesson this script teaches: in a
# REAL company, you would never do this - you'd use a long-lived IAM role via
# GitHub's OIDC federation (no static keys stored anywhere). That pattern
# needs a persistent AWS account, which a rotating training sandbox doesn't
# give you. See docs/16-cicd-continuous-deployment.md for the full
# explanation and how to graduate to OIDC on a real AWS account later.
#
# =============================================================================
# GITHUB TOKEN — WHICH ONE, AND WHY
# =============================================================================
# You need a GitHub Personal Access Token (PAT) that can (a) push code and
# (b) manage this repo's Actions secrets. Two options:
#
#   OPTION A (recommended) — Fine-grained PAT
#     https://github.com/settings/tokens?type=beta
#     - Repository access: "Only select repositories" -> choose this one repo
#     - Permissions needed:
#         Contents        : Read and write   (to push code)
#         Actions         : Read and write   (to manage/re-run workflow runs)
#         Secrets         : Read and write   (to create the AWS_* secrets)
#         Metadata        : Read-only        (required baseline, auto-selected)
#
#   OPTION B — Classic PAT
#     https://github.com/settings/tokens/new
#     - Scopes needed: `repo` (full control, needed to push) + `workflow`
#       (needed because we push a workflow file under .github/workflows/)
#
# Either way: copy the token now - GitHub only shows it once. This script
# never writes it to disk, to a config file, or to your shell history.
#
# Usage: ./scripts/advanced/06-setup-cicd.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header()  { echo -e "\n${BLUE}================================${NC}\n${BLUE}$1${NC}\n${BLUE}================================${NC}\n"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info()    { echo -e "${YELLOW}ℹ️  $1${NC}"; }
print_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }

print_header "Thermos Level 2: CI/CD Setup (push to GitHub + enable CD)"

print_warn "KodeKloud session credentials are TEMPORARY. This script wires up CD for"
print_warn "the rest of THIS session only - re-run it next session to refresh secrets."
print_info "See docs/16-cicd-continuous-deployment.md for the full explanation."
echo ""
read -r -p "Understood - continue? (yes/no): " ack
if [ "$ack" != "yes" ]; then
  print_info "Cancelled."
  exit 0
fi

# =============================================================================
# Prerequisites
# =============================================================================
command -v git >/dev/null 2>&1 || { print_error "git not found. Run ./scripts/01-setup.sh first."; exit 1; }
command -v curl >/dev/null 2>&1 || { print_error "curl not found."; exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { print_error "AWS credentials not configured - run 'aws configure' first."; exit 1; }

GH_CLI_AVAILABLE=0
command -v gh >/dev/null 2>&1 && GH_CLI_AVAILABLE=1

# =============================================================================
# Step 1: Collect repo URL + token
# =============================================================================
print_header "STEP 1/4: GitHub Repository Details"

print_info "Create an empty repository on GitHub first (do NOT initialize it with a"
print_info "README) if you haven't already: https://github.com/new"
echo ""
read -r -p "GitHub repository URL (e.g. https://github.com/<you>/<repo>.git): " REPO_URL
if [ -z "$REPO_URL" ]; then
  print_error "No repository URL provided. Aborting."
  exit 1
fi

# Extract owner/repo from the URL for the GitHub API calls later.
OWNER_REPO="$(echo "$REPO_URL" | sed -E 's#^https://github\.com/##; s#^git@github\.com:##; s#\.git$##')"
if [[ ! "$OWNER_REPO" =~ ^[^/]+/[^/]+$ ]]; then
  print_error "Couldn't parse owner/repo from '$REPO_URL'. Expected https://github.com/<owner>/<repo>.git"
  exit 1
fi
print_success "Target repository: $OWNER_REPO"

echo ""
print_info "Paste your GitHub PAT (see the comment header of this script for which"
print_info "type and permissions to create). Input is hidden."
read -r -s -p "GitHub token: " GH_TOKEN
echo ""
if [ -z "$GH_TOKEN" ]; then
  print_error "No token provided. Aborting."
  exit 1
fi

# Sanity-check the token can see the repo before we do anything destructive.
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER_REPO}")
if [ "$HTTP_CODE" != "200" ]; then
  print_error "GitHub API couldn't access ${OWNER_REPO} with that token (HTTP ${HTTP_CODE})."
  print_info "Check: the repo exists, the token isn't expired, and it has Contents +"
  print_info "Actions + Secrets permission on this repo (see this script's header comment)."
  unset GH_TOKEN
  exit 1
fi
print_success "Token can access ${OWNER_REPO}"

# =============================================================================
# Step 2: Initialize git and push
# =============================================================================
print_header "STEP 2/4: Initializing and Pushing the Project"

if [ ! -d ".git" ]; then
  git init -q
  git checkout -q -b main 2>/dev/null || git branch -m main
  print_success "Initialized a new git repository (branch: main)"
else
  print_info "git repository already exists - reusing it"
fi

if [ -z "$(git config user.email 2>/dev/null)" ]; then
  git config user.email "thermos-fresher@example.com"
  git config user.name "Thermos Fresher"
  print_info "Set a placeholder git identity (change with 'git config --global user.name/email')"
fi

git add -A
if git diff --cached --quiet; then
  print_info "Nothing new to commit"
else
  git commit -q -m "Thermos: initial commit via 06-setup-cicd.sh"
  print_success "Committed current project state"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

print_info "Pushing to ${OWNER_REPO} (branch: main)..."
# The token is passed as a one-off HTTP header via -c, NOT written to
# .git/config and NOT embedded in the remote URL - it never touches disk or
# shell history beyond this single command's process environment.
AUTH_HEADER="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
if git -c http."https://github.com/".extraheader="$AUTH_HEADER" push -u origin main; then
  print_success "Pushed to https://github.com/${OWNER_REPO}"
else
  print_error "git push failed - see the error above (common cause: branch protection, or"
  print_error "the repo already has commits that conflict with this one)."
  unset GH_TOKEN AUTH_HEADER
  exit 1
fi

# =============================================================================
# Step 3: Register AWS credentials as GitHub Actions secrets
# =============================================================================
print_header "STEP 3/4: Registering AWS Credentials as GitHub Secrets"

AWS_ACCESS_KEY_ID_VAL="$(aws configure get aws_access_key_id || true)"
AWS_SECRET_ACCESS_KEY_VAL="$(aws configure get aws_secret_access_key || true)"
AWS_SESSION_TOKEN_VAL="$(aws configure get aws_session_token || echo "${AWS_SESSION_TOKEN:-}")"
AWS_REGION_VAL="$(aws configure get region || echo "us-east-1")"

if [ -z "$AWS_ACCESS_KEY_ID_VAL" ] || [ -z "$AWS_SECRET_ACCESS_KEY_VAL" ]; then
  print_error "Could not read AWS credentials via 'aws configure get'. Run 'aws configure' first."
  unset GH_TOKEN AUTH_HEADER
  exit 1
fi
if [ -z "$AWS_SESSION_TOKEN_VAL" ]; then
  print_warn "No AWS session token found - this is normal for a real IAM user, but on the"
  print_warn "KodeKloud Playground you almost always have one. Double-check 'aws configure list'."
fi

set_secret() {
  local name="$1"
  local value="$2"
  [ -z "$value" ] && { print_info "  skipping ${name} (empty)"; return; }

  if [ "$GH_CLI_AVAILABLE" -eq 1 ]; then
    if echo -n "$value" | GH_TOKEN="$GH_TOKEN" gh secret set "$name" --repo "$OWNER_REPO" >/dev/null 2>&1; then
      print_success "Set secret: ${name} (via gh CLI)"
    else
      print_error "Failed to set secret ${name} via gh CLI"
    fi
    return
  fi

  # No gh CLI: encrypt with the repo's public key ourselves (libsodium sealed
  # box, as required by the GitHub Secrets API) using Python + PyNaCl.
  python3 -c "import nacl.public" >/dev/null 2>&1 || pip install pynacl -q --break-system-packages >/dev/null 2>&1

  local key_json key_id public_key
  key_json="$(curl -s -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${OWNER_REPO}/actions/secrets/public-key")"
  key_id="$(echo "$key_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['key_id'])" 2>/dev/null)"
  public_key="$(echo "$key_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])" 2>/dev/null)"

  if [ -z "$key_id" ] || [ -z "$public_key" ]; then
    print_error "Could not fetch the repo's public key for ${name} - set it manually instead:"
    print_info "  GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret"
    print_info "  Name: ${name}"
    return
  fi

  local encrypted
  encrypted="$(python3 - "$public_key" "$value" <<'PYEOF'
import sys, base64
from nacl import encoding, public
pub_key = public.PublicKey(sys.argv[1].encode("utf-8"), encoding.Base64Encoder())
sealed_box = public.SealedBox(pub_key)
encrypted = sealed_box.encrypt(sys.argv[2].encode("utf-8"))
print(base64.b64encode(encrypted).decode("utf-8"))
PYEOF
  )"

  if [ -z "$encrypted" ]; then
    print_error "Encryption failed for ${name} (PyNaCl unavailable / no network to install it)."
    print_info "Set it manually: GitHub repo -> Settings -> Secrets and variables -> Actions"
    print_info "  Name: ${name}   Value: <paste from your terminal - do not commit it>"
    return
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${OWNER_REPO}/actions/secrets/${name}" \
    -d "{\"encrypted_value\":\"${encrypted}\",\"key_id\":\"${key_id}\"}")

  if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
    print_success "Set secret: ${name}"
  else
    print_error "Failed to set secret ${name} (HTTP ${http_code})"
  fi
}

set_secret "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID_VAL"
set_secret "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY_VAL"
set_secret "AWS_SESSION_TOKEN" "$AWS_SESSION_TOKEN_VAL"
set_secret "AWS_REGION" "$AWS_REGION_VAL"

# Scrub secrets from the current shell's memory as soon as we're done with them.
unset GH_TOKEN AUTH_HEADER AWS_ACCESS_KEY_ID_VAL AWS_SECRET_ACCESS_KEY_VAL AWS_SESSION_TOKEN_VAL

# =============================================================================
# Step 4: Done
# =============================================================================
print_header "STEP 4/4: CI/CD Is Live"

print_success "Code pushed to https://github.com/${OWNER_REPO}"
print_success "AWS credentials registered as Actions secrets"
echo ""
print_info "From now on, until your KodeKloud session expires:"
print_info "  - Every 'git push' to main touching terraform-docker/, terraform-eks/, or"
print_info "    kubernetes/ triggers .github/workflows/cd.yml"
print_info "  - It reads .thermos/active-stack to know whether to apply against the"
print_info "    Docker/EC2 stack or the Kubernetes/EKS stack (whichever you deployed)"
print_info "  - Watch it run: https://github.com/${OWNER_REPO}/actions"
echo ""
print_warn "When you start a NEW KodeKloud session, re-run this script to refresh the"
print_warn "AWS secrets - the old session's credentials will no longer work."
