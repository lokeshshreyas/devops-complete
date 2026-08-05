# 🚀 Thermos — Simplified DevOps Project (Fresher Edition)

## KodeKloud AWS Playground Compatible

> **Project Duration:** 60–90 minutes | **Difficulty:** Beginner | **Cloud:** AWS
> **Stack:** React frontend + Flask backend + PostgreSQL, shipped with Docker Compose and a single Terraform file

---

## 📖 Quick Start

**New to this project? Start here:**

📘 **[RUNBOOK.md](RUNBOOK.md)** — complete, copy-pasteable, step-by-step deployment guide

### Fastest path (one command each)

```bash
# 1. Install every tool you need (Docker, Terraform, AWS CLI, git, jq) — idempotent, safe to re-run
./scripts/01-setup.sh

# 2. Validate the app locally, deploy to AWS, and verify — all in one go
./scripts/03-deploy.sh

# 3. When you're done (always do this on KodeKloud!)
./scripts/07-destroy.sh
```
---

## 📘 New to This? Start Here

**First time deploying to AWS?** Follow the [Complete Walkthrough](docs/14-complete-walkthrough.md) — it covers every single step from installing tools to testing the live app, with no steps skipped.

**Want to know how to check if things are working?** See [Checking, Verifying, and Monitoring](docs/13-checking-and-monitoring.md) — a detailed guide on checking resources locally and in AWS, reading logs, and troubleshooting.

---


That's it. Each script is also documented individually below and in [docs/](docs/).

---

## 🚀 Level 2 (optional): Kubernetes, CI/CD, Remote State

Once you're comfortable with the core workshop above, optional add-ons let you practice more
advanced patterns — none of them are required, and none of them change how Level 1 works:

```bash
# Remote Terraform state (S3 + DynamoDB) instead of a local .tfstate file
./scripts/advanced/01-setup-backend.sh          # see docs/09-remote-terraform-state.md

# Kubernetes on EKS instead of Docker Compose on one EC2 instance
./scripts/advanced/02-eks-up.sh                 # create the cluster (~10-15 min)
./scripts/advanced/03-k8s-deploy.sh             # build, push, deploy
./scripts/advanced/04-k8s-destroy.sh            # tear down when done - see docs/11-kubernetes-eks-optional.md

# CI: push this project to your own GitHub repo and .github/workflows/ci.yml runs
# automatically - validates Terraform/Docker/scripts/manifests, no AWS credentials needed
# see docs/10-cicd-pipeline.md

# CD (opt-in): also auto-apply every push to whichever stack you deployed above
./scripts/advanced/06-setup-cicd.sh             # see docs/16-cicd-continuous-deployment.md
```

⚠️ EKS costs more and takes longer to provision than the core workshop's single EC2
instance — read [docs/11-kubernetes-eks-optional.md](docs/11-kubernetes-eks-optional.md)
before running `02-eks-up.sh`.

---

## 🏗️ Architecture

```
Your Browser
     │
     ▼
http://<EC2_PUBLIC_IP>
     │
┌────────────────────────────────────────────┐
│  EC2 Instance (t3.medium, single AZ)         │
│  Docker Engine                              │
│   ├── thermos-frontend  (Nginx :80)         │
│   ├── thermos-backend   (Flask :5000)       │
│   └── thermos-postgres  (PostgreSQL :5432)  │
│  All containers share one Docker network    │
└────────────────────────────────────────────┘
     ▲
[AWS Security Group]
 ├─ 22   SSH     (admin access)
 ├─ 80   HTTP    (frontend)
 ├─ 443  HTTPS   (reserved, unused today)
 └─ 5000 HTTP    (backend API, for debugging)
```

No EKS, no Kubernetes, no NAT gateways, no multi-AZ — this project intentionally uses the
smallest possible AWS footprint (1 VPC, 1 subnet, 1 EC2 instance) so it fits comfortably
inside a KodeKloud AWS Playground session. See
**[docs/02-architecture.md](docs/02-architecture.md)** for the full breakdown and
**[docs/03-kodekloud-aws-playground-limits.md](docs/03-kodekloud-aws-playground-limits.md)**
for the platform limits this design respects.

---

## 📁 Directory Structure

```
thermos-devops-project/
├── README.md .......................... You are here
├── RUNBOOK.md ......................... Step-by-step deployment guide (start here!)
├── CHANGELOG.md ........................ What changed between versions, and why
├── .gitignore .......................... Keeps Terraform state, .pem keys, node_modules, etc. out of git
├── docker-compose.yml .................. Local development stack (frontend + backend + db)
├── .thermos/ ............................ Level 2 (optional): tiny state used by the CD workflow
│   └── active-stack .................... "docker", "eks", or "none" - written by the deploy scripts
│
├── docs/ ............................... Numbered reference documentation
│   ├── 01-introduction.md
│   ├── 02-architecture.md
│   ├── 03-kodekloud-aws-playground-limits.md
│   ├── 04-prerequisites-and-tools.md
│   ├── 05-local-validation.md
│   ├── 06-terraform-deployment.md
│   ├── 07-troubleshooting.md
│   ├── 08-cleanup-and-cost-control.md
│   ├── 09-remote-terraform-state.md ..... Level 2 (optional)
│   ├── 10-cicd-pipeline.md .............. Level 2 (optional) - CI (validation only)
│   ├── 11-kubernetes-eks-optional.md .... Level 2 (optional)
│   ├── 12-eks-architecture-and-networking.md ... Level 2 (optional) - internal design + traffic flow
│   ├── 13-checking-and-monitoring.md .... How to verify a live deployment is healthy
│   ├── 14-complete-walkthrough.md ....... One full run, start to finish, with real output
│   ├── 15-terraform-docker-vs-eks.md .... Level 1 vs Level 2, compared side by side
│   └── 16-cicd-continuous-deployment.md . Level 2 (optional) - CD (auto-deploy on push)
│
├── interview-qa/ ....................... Practice Q&A for fresher DevOps interviews
│   ├── docker-questions.md
│   ├── terraform-questions.md
│   └── aws-questions.md
│
├── scripts/ ............................ All automation lives here, run in numeric order
│   ├── 01-setup.sh .................. Installs Docker/Terraform/AWS CLI/git/jq
│   ├── 02-validate.sh ............... Validates the app locally with Docker Compose
│   ├── 03-deploy.sh ................. Core Terraform deploy to AWS (interactive)
│   ├── 04-verify.sh ................. Health-checks the live deployment over HTTP
│   ├── 05-status.sh ................. Quick dashboard of local + AWS state
│   ├── 06-ssh.sh ..................... SSH into the EC2 box, auto-detects the key
│   ├── 07-destroy.sh ................. One-command full teardown (AWS + local Docker)
│   └── advanced/ ..................... Level 2 (optional) automation, numbered in run order
│       ├── 01-setup-backend.sh ...... Bootstrap S3 + DynamoDB remote Terraform state
│       ├── 02-eks-up.sh ............. Create the EKS cluster + ECR repos
│       ├── 03-k8s-deploy.sh ......... Build, push, and deploy the app to EKS
│       ├── 04-k8s-destroy.sh ........ Tear down the k8s app + EKS cluster
│       ├── 05-destroy-backend.sh .... Tear down the remote state backend (run last)
│       ├── 06-setup-cicd.sh ......... Push to GitHub + register CD secrets (opt-in)
│       └── 07-cd-apply.sh ........... Non-interactive apply used by cd.yml (or run by hand)
│
├── src/ ................................. Application source code (identical on every path)
│   ├── backend/ ....................... Flask API
│   ├── frontend/ ....................... React app
│   └── database/ ....................... PostgreSQL init script
│
├── terraform-docker/ .................... REQUIRED: core workshop AWS infrastructure
│   ├── main.tf .......................... VPC + EC2 + security group + auto SSH key
│   ├── variables.tf ..................... Inputs, with KodeKloud-safe validation rules
│   ├── outputs.tf ........................ Public IP, SSH command, etc.
│   ├── providers.tf ...................... AWS provider + Terraform version pin
│   ├── user_data.sh ...................... EC2 boot script (no GitHub required)
│   ├── backend/ ........................... Level 2: S3 + DynamoDB bootstrap module (local state)
│   ├── backend.tf ......................... Level 2: inactive template until 01-setup-backend.sh runs
│   ├── backend.tf.template ................ Level 2: pristine copy, restored by 05-destroy-backend.sh
│   └── thermos-key.pem ................... Auto-generated after 'terraform apply' (gitignored)
│
├── terraform-eks/ ....................... Level 2 (optional): EKS cluster + ECR repos
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── backend.tf ......................... Level 2: inactive template until 01-setup-backend.sh runs
│   ├── backend.tf.template ................ Level 2: pristine copy, restored by 05-destroy-backend.sh
│   └── README.md
│
├── kubernetes/ ........................... Level 2 (optional): manifests for terraform-eks
│   ├── 00-secrets.yaml
│   ├── 01-postgres.yaml
│   ├── 02-backend.yaml
│   └── 03-frontend.yaml
│
└── .github/workflows/
    ├── ci.yml ............................ Level 2 (optional): CI validation, no deployment
    └── cd.yml ............................ Level 2 (optional, opt-in): CD - auto-deploy on push
```

> **Two levels, clearly separated.** Level 1 (`terraform-docker/`, `docker-compose.yml`,
> `scripts/03-deploy.sh`) is the **required**, self-contained workshop — nothing outside it is
> needed to complete [RUNBOOK.md](RUNBOOK.md). Level 2 (`terraform-eks/`, `kubernetes/`,
> `.github/workflows/`, `scripts/advanced/` and friends) is **entirely optional** —
> for when you want to practice Kubernetes, CI/CD, and remote Terraform state without
> touching or complicating the core path. See [CHANGELOG.md](CHANGELOG.md) for the full
> history of what changed and why.

## 🛠️ Design notes

- **Two levels, clearly separated:** Level 1 (`terraform-docker/`, `docker-compose.yml`,
  `scripts/03-deploy.sh`) is the required, self-contained workshop. Level 2 (`terraform-eks/`,
  `kubernetes/`, `.github/workflows/`, `scripts/advanced/` and friends) is entirely
  optional and doesn't need to be touched to complete [RUNBOOK.md](RUNBOOK.md).
- **`terraform-docker/main.tf`** auto-generates an SSH key pair (so `ssh_command` output is a
  real, working command) and uploads your local code directly to the instance via a `file`
  provisioner — no GitHub account or `REPO_URL` edit needed.
- **`instance_type` / `node_instance_type` validation blocks** reject instance types the
  KodeKloud AWS Playground doesn't allow, failing fast at `terraform plan` instead of at
  `apply` time.
- **`.thermos/active-stack`** is a one-line marker (`docker`, `eks`, or `none`) written by
  `03-deploy.sh` and `scripts/advanced/03-k8s-deploy.sh` so later automation — including the
  optional CD workflow — always knows which stack is currently live, without guessing.
- **Full change history:** see [CHANGELOG.md](CHANGELOG.md) for every version-to-version
  diff and the reasoning behind each change.

### Level 2 (optional): Kubernetes, CI/CD, Remote State

| File | Purpose |
|---|---|
| `terraform-docker/backend/main.tf` + `scripts/advanced/01-setup-backend.sh` / `05-destroy-backend.sh` | Bootstraps an S3 + DynamoDB remote Terraform state backend shared by both modules — `03-deploy.sh`/`07-destroy.sh` need no changes to use it |
| `terraform-eks/main.tf` | A minimal, self-managed-node EKS cluster + ECR repos, sized within KodeKloud's EKS limits |
| `kubernetes/00–03*.yaml` | Deployment/Service/Secret manifests for the same app, running on Kubernetes instead of Docker Compose |
| `scripts/advanced/02-eks-up.sh`, `03-k8s-deploy.sh`, `04-k8s-destroy.sh` | Provision the EKS cluster, build/push/deploy, and tear down in the correct order |
| `.github/workflows/ci.yml` | CI validation (Terraform validate, Docker build, ShellCheck, Kubernetes manifest validation) if you push this project to GitHub — no deployment, no secrets required |
| `scripts/advanced/06-setup-cicd.sh` + `.github/workflows/cd.yml` + `scripts/advanced/07-cd-apply.sh` | Opt-in CD: pushes this project to your own GitHub repo, registers AWS secrets, and auto-applies future pushes to whichever stack (`docker`/`eks`) is currently deployed |
| `docs/09–12`, `docs/16` | Dedicated docs for remote state, CI, CD, and the Kubernetes/EKS path (provisioning, internal design, and client traffic flow) |

---

## 🎓 Learning Path

- **Level 1 (required, beginner):** Docker Compose, single EC2 instance, minimal Terraform,
  manual deploy. This is the KodeKloud workshop — see [RUNBOOK.md](RUNBOOK.md).
- **Level 2 (optional, intermediate):** the same application on EKS, with remote Terraform
  state and a CI validation pipeline — all inside *this* project, see the section above.
- **Next step (advanced):** graduate to the full `ecommerce-devops-project` — ArgoCD GitOps,
  per-microservice Kubernetes manifests, a complete build-and-deploy CI/CD pipeline, and
  multi-service architecture.
- **Beyond that:** service mesh, autoscaling, multi-AZ high availability, production
  observability.

---

**Built for DevOps freshers. Start with [RUNBOOK.md](RUNBOOK.md).**
