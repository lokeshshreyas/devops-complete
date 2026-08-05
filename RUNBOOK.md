# 📘 Thermos RUNBOOK

Complete, ordered, copy-pasteable instructions for deploying Thermos to a **KodeKloud AWS
Playground** session. This replaces the old `KODEKLOUD_README.md`, `QUICK_START.md`, and
`DEPLOYMENT_CHECKLIST.txt` — everything from those three files lives here now, in one order.

⏰ **KodeKloud sessions expire in 3 hours.** This whole run book — setup, deploy, test,
cleanup — takes about 60–90 minutes, leaving a comfortable buffer.

> **v2 update:** deployment no longer needs a GitHub account, a repo push, or an edited
> `REPO_URL`, and SSH access works out of the box with an auto-generated key. See
> [CHANGELOG.md](CHANGELOG.md) for the full list of what changed and why.

---

## 0. Before you start

- [ ] You have a KodeKloud AWS Playground session open (region **us-east-1**)
- [ ] You have copied the playground's AWS credentials somewhere safe
- [ ] You have a terminal open in this project's root directory

Read **[docs/03-kodekloud-aws-playground-limits.md](docs/03-kodekloud-aws-playground-limits.md)**
at least once — it explains exactly why this project uses a `t3.medium`, a single AZ, and no
NAT gateway.

---

## 1. Install tools (5–10 min)

Use the new fast installer (recommended):

```bash
chmod +x scripts/*.sh
./scripts/01-setup.sh
```

This installs/upgrades Docker, Terraform, AWS CLI v2, git, and jq, and is safe to re-run —
it skips anything already installed. See
**[docs/04-prerequisites-and-tools.md](docs/04-prerequisites-and-tools.md)** for what it does
step by step and manual install instructions per OS.

Then configure AWS credentials from the playground:

```bash
aws configure
# AWS Access Key ID:     <paste from KodeKloud>
# AWS Secret Access Key: <paste from KodeKloud>
# Default region name:   us-east-1
# Default output format: json

aws sts get-caller-identity   # should print your KodeKloud account details
```

---

## 2. Validate locally (10 min, optional but recommended)

Catch Docker/build issues before touching AWS:

```bash
./scripts/02-validate.sh
```

This builds all three images, starts them with Docker Compose, waits for health checks, and
tears the local stack back down. See
**[docs/05-local-validation.md](docs/05-local-validation.md)** for what "success" looks like
and how to debug a failure.

---

## 3. Deploy to AWS (10–15 min)

### Option A — one command (recommended)

```bash
./scripts/03-deploy.sh
```

Runs setup (if needed) → local validation (if you didn't skip it) → `terraform apply` →
post-deploy health checks, and prints the final URL. Pass `-y` to skip the "yes/no" prompt.

### What the script actually does

`./scripts/03-deploy.sh` will:
1. Verify Terraform / AWS CLI / git are installed
2. Verify AWS credentials work
3. Run `terraform init` and `terraform plan`
4. Ask you to confirm (`type 'yes'`)
5. Run `terraform apply`
6. Print the EC2 IP, application URL, and SSH command

```
📍 EC2 Instance IP: 1.2.3.4
🌐 Application URL: http://1.2.3.4
🔐 SSH Command: ssh -i <path-to-key.pem> ubuntu@1.2.3.4
```

Details and the underlying `terraform-docker/main.tf` resources are documented in
**[docs/06-terraform-deployment.md](docs/06-terraform-deployment.md)**.

> **No GitHub account needed.** Terraform ships your local `docker-compose.yml` and `src/`
> straight to the EC2 instance itself (via a "file" provisioner in `main.tf`) as part of
> `terraform apply` — there's no repository to push, fork, or point a `REPO_URL` at. See
> [docs/06-terraform-deployment.md](docs/06-terraform-deployment.md) for how this works.

---

## 4. Wait for services to start (2–3 min)

```bash
# Watch it come up automatically, with retries:
./scripts/04-verify.sh

# ...or manually:
curl http://<EC2_IP>/
curl http://<EC2_IP>:5000/health
```

Or SSH in and tail the logs directly:

```bash
./scripts/06-ssh.sh       # NEW: no need to remember the IP or key path
docker compose logs -f
```

---

## 5. Test the application (5–10 min)

1. Open `http://<EC2_IP>` in your browser
2. Register an account (any username/email/password)
3. Log in
4. Add a bookmark (URL + title + tags)
5. Confirm it appears on your dashboard

---

## 6. Check status any time

```bash
./scripts/05-status.sh
```

Shows local Docker container state and, if Terraform has been applied, the live AWS
instance state, public IP, and how long it's been running — a fast way to remember "did I
already destroy this?" before your session ends.

---

## 7. Cleanup — always do this before your session ends (5 min)

```bash
./scripts/07-destroy.sh
```

This runs `terraform destroy` **and** prunes local Docker containers/images left over from
local validation. See
**[docs/08-cleanup-and-cost-control.md](docs/08-cleanup-and-cost-control.md)** for why this
matters even on a free playground session.

You'll be asked to type `yes` to confirm before anything is destroyed.

---

## Port reference

| Port | Service | When to open it |
|---|---|---|
| 22 | SSH | From the start — needed to inspect setup/boot logs |
| 80 | Frontend (Nginx) | Once deployed — this is the URL you'll browse to |
| 5000 | Backend API (Flask) | Before testing — the frontend calls this directly for debugging |
| 443 | HTTPS | Not used in this workshop; reserved for future TLS work |
| 5432 | PostgreSQL | **Never expose publicly** — internal Docker network only |

---

## Time budget (typical)

```
Install tools ................. 5–10 min   (skip if already installed)
Local validation ............... 10 min    (optional)
AWS credential setup ............ 5 min
Terraform deploy ............... 10–15 min
Wait for boot .................... 3 min
App testing ..................... 10 min
Cleanup ........................... 5 min
                                ─────────
Total ~50–70 min, inside the 3-hour session
```

---

## Troubleshooting

Full troubleshooting guide: **[docs/07-troubleshooting.md](docs/07-troubleshooting.md)**.
Quick links for the most common issues:

- Docker Compose won't start → docs/07, section "Docker Compose"
- Backend can't reach the database → docs/07, section "Database connectivity"
- `terraform apply` fails → docs/07, section "Terraform"
- Can't SSH into the EC2 instance → docs/07, section "SSH access"
- App loads but shows a 502 → docs/07, section "502 errors"

---

## FAQ

**Why not use the full EKS/Terraform setup from the ecommerce project?**
It's great for production and for learning Kubernetes, but it's too much for a first,
3-hour deployment. This simplified path teaches the same core ideas (IaC, VPC, security
groups, containers) without the extra abstraction layers.

**Can I reuse this pattern for other projects?**
Yes — one EC2 instance + Docker Compose + a single Terraform file works for any small
3-tier app (Node, Python, Go, etc.).

**What if I break something?**
Run `./scripts/07-destroy.sh` and redeploy with `./scripts/03-deploy.sh`. Terraform is
idempotent, so a fresh `apply` recreates everything cleanly.

**What's next after this workshop?**
This project now has its own optional "Level 2": Kubernetes on EKS
(`./scripts/advanced/02-eks-up.sh` → `./scripts/advanced/03-k8s-deploy.sh`), remote Terraform state
(`./scripts/advanced/01-setup-backend.sh`), a CI validation pipeline (`.github/workflows/ci.yml`),
and an opt-in CD pipeline that auto-deploys on push (`./scripts/advanced/06-setup-cicd.sh`) — see
[docs/09-remote-terraform-state.md](docs/09-remote-terraform-state.md),
[docs/10-cicd-pipeline.md](docs/10-cicd-pipeline.md),
[docs/11-kubernetes-eks-optional.md](docs/11-kubernetes-eks-optional.md), and
[docs/16-cicd-continuous-deployment.md](docs/16-cicd-continuous-deployment.md). Beyond that, look
at the `ecommerce-devops-project` structure for the full production pattern: ArgoCD GitOps,
per-microservice manifests, and a complete build-and-deploy pipeline.
