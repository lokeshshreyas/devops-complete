# 11. Kubernetes on EKS (Optional "Level 2")

**This is optional and separate from the core workshop.** [RUNBOOK.md](../RUNBOOK.md) — the
required path — deploys to a single EC2 instance with Docker Compose and never touches EKS.
Use this section once you're comfortable with that and want to see the same application
running on real Kubernetes.

## ⚠️ CRITICAL: Two-Step Deployment Required

EKS deployment requires **TWO separate scripts run in exact order**:

```bash
# STEP 1: Create infrastructure (~10-15 minutes)
./scripts/advanced/02-eks-up.sh

# STEP 2: Deploy the application (~5-10 minutes)
./scripts/advanced/03-k8s-deploy.sh

# STEP 3: WAIT for NLB provisioning (~1-2 minutes AFTER 03-k8s-deploy.sh finishes)
```

`02-eks-up.sh` will ask which **node instance type** to use before it runs Terraform - press
Enter to accept the default (`t3.medium`, recommended) or type `t3.micro`. To skip the
prompt, pass `./scripts/advanced/02-eks-up.sh --node-instance-type=t3.micro` directly. See
`terraform-eks/variables.tf` for why `t3.medium` is recommended over `t3.micro`.

**Total time from start to browser-accessible URL: 20–30 minutes.**

> **Do NOT check your browser after only 5 minutes.** The EKS control plane takes 10–15 minutes to create, worker nodes take 1–2 minutes to boot and join, Docker images take 2–5 minutes to build and push, and the AWS Network Load Balancer takes an additional 1–2 minutes to provision after the script prints a URL. This is normal AWS behavior, not a bug.

**If you only ran `02-eks-up.sh` (or `terraform apply` directly), you have an empty cluster with no pods and no LoadBalancer.** Run `./scripts/advanced/03-k8s-deploy.sh` to actually deploy the application.

---

## ⚠️ Read this before you start

- **EKS is not part of KodeKloud's free/beginner-friendly resource set the way EC2 t3.medium
  is.** The control plane itself costs money for every hour it exists, on top of the worker
  node EC2 instances and the Elastic Load Balancer — check
  [docs/03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md) for
  the exact EKS limits (node types, node count) this project respects.
- **Creating the cluster takes 10-15 minutes** — budget for that inside your 3-hour session.
- **Destroy it as soon as you're done** (`./scripts/advanced/04-k8s-destroy.sh`) — don't leave it running
  for the rest of your session the way you might leave the simple EC2 deployment up for a
  bit longer.

## What gets created

A separate, minimal EKS setup in `terraform-eks/main.tf`:

- A dedicated VPC (`10.1.0.0/16`, separate from the core workshop's `10.0.0.0/16`) with 2
  public subnets across 2 Availability Zones (EKS requires at least 2)
- An EKS cluster (control plane) and a **self-managed** worker node Auto Scaling Group
  (Launch Template + ASG, joined via an EKS Access Entry) — not an `aws_eks_node_group`.
  The KodeKloud AWS Playground has an explicit IAM deny on `eks:CreateNodegroup`, so managed
  node groups can't be created there at all (confirmed by KodeKloud staff); this project
  works around it with plain EC2 instances instead. See
  [docs/03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md#eks-node-groups-are-blocked-in-the-playground).
- Nodes sized within KodeKloud's EKS limits: instance type validated against
  `t2`/`t3` `nano`–`medium` only, 1-3 nodes (default 1 - enough for the 3 pods this project
  runs; see below)
- Two ECR repositories (`thermos-backend`, `thermos-frontend`) with image scanning enabled —
  Kubernetes pulls images from here, not from your local Docker

**IAM roles use KodeKloud's required exact names.** The playground scopes EKS permissions
around two specific role names: `eksClusterRole` and `AmazonEKSNodeRole`. `terraform-eks/main.tf`
looks these up via Terraform data sources rather than creating custom-named roles, and
`scripts/advanced/02-eks-up.sh` creates them first (with the right trust policy and managed policies
attached) if they don't already exist in your account, or safely reuses them if they do. See
[docs/03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md).

## The Kubernetes manifests (`kubernetes/`)

Four files, applied in order:

| File | What it creates |
|---|---|
| `00-secrets.yaml` | A `Secret` with the same demo credentials already used in `docker-compose.yml` (`thermos`/`thermos`) |
| `01-postgres.yaml` | Postgres `Deployment` + `Service` named exactly `postgres` — matches the hostname already in `DATABASE_URL`, so nothing in the app needed to change |
| `02-backend.yaml` | Flask backend `Deployment` (1 replica) + `Service` named exactly `thermos-backend` — matches `nginx.conf`'s `proxy_pass http://thermos-backend:5000`, so the *same* frontend image from `docker-compose.yml` works unmodified |
| `03-frontend.yaml` | React/Nginx frontend `Deployment` (1 replica) + a `LoadBalancer` `Service` (provisions a real AWS ELB) |

**Why 1 replica each, not more?** KodeKloud caps EKS at **3 pods per namespace**. With
`postgres` + `thermos-backend` + `thermos-frontend` at 1 replica each, this project sits at
exactly 3 pods — the maximum allowed, with zero headroom for a 4th. Don't bump any of these
`replicas:` values up without also reducing another, or the extra pod will fail to schedule
(or worse, trigger the playground's automatic remediation). Every container's resource
`limits.cpu` is also capped at `200m` (under the playground's 256 millicore per-pod limit)
and `limits.memory` at 256Mi or less (under the 512Mi per-pod limit).

Notice what *didn't* need to change: the actual application code, the Dockerfiles, and even
the environment variable names are identical to the Docker Compose setup. Only the
orchestration layer changed — that's the point of this exercise.

**Data persistence note:** `01-postgres.yaml` uses an `emptyDir` volume, not a
`PersistentVolumeClaim`. A `PersistentVolumeClaim` on EKS needs the AWS EBS CSI driver
installed as a cluster add-on first — an extra step intentionally left out of this workshop
to keep it focused on the core Deployment/Service/Secret concepts. This means Postgres data
is lost if its pod restarts, which is an acceptable tradeoff for a short learning session
(and is called out explicitly in `01-postgres.yaml`'s comments).

## Deploy it

```bash
chmod +x scripts/advanced/02-eks-up.sh scripts/advanced/03-k8s-deploy.sh scripts/advanced/04-k8s-destroy.sh

./scripts/advanced/02-eks-up.sh        # 1. Ensure IAM roles exist, then create the EKS cluster + ECR repos (~10-15 min)
./scripts/advanced/03-k8s-deploy.sh    # 2. Build, push, and deploy the app
```

`02-eks-up.sh` first checks whether `eksClusterRole` and `AmazonEKSNodeRole` already exist in
your account (via `aws iam get-role`), creating them with the right trust policy and managed
policies attached if they don't, before running `terraform apply` — this is what makes the
cluster creation work within the playground's IAM restrictions without you doing anything
extra.

`03-k8s-deploy.sh` builds the backend/frontend images from the exact same Dockerfiles as
`docker-compose.yml`, pushes them to the ECR repos Terraform created, points `kubectl` at
the new cluster, substitutes the real image URIs into the manifests, and applies them in
order — waiting for each `Deployment` to roll out before moving to the next.

## Check on it

```bash
kubectl get pods                          # all pods should show Running
kubectl get svc thermos-frontend          # find the LoadBalancer's external hostname
kubectl logs -f deploy/thermos-backend    # tail backend logs
kubectl describe pod <pod-name>           # debug a pod that's not starting
```

## Tear it down

```bash
./scripts/advanced/04-k8s-destroy.sh
```

This deletes the Kubernetes resources first (specifically the `LoadBalancer` Service, so AWS
releases the associated ELB) before running `terraform destroy` on the EKS cluster, worker
node ASG, VPC, and ECR repos — order matters here, so always use this script rather than
running `terraform destroy` directly in `terraform-eks/`.

## What this teaches

- `Deployment`, `Service` (`ClusterIP` vs `LoadBalancer`), and `Secret` — the three most
  fundamental Kubernetes objects
- How in-cluster DNS (`Service` names) replaces the Docker Compose network aliases you
  already know
- Readiness/liveness probes as the Kubernetes equivalent of Docker Compose healthchecks
- Building images for a registry (ECR) instead of just running them locally
- Why destroy order matters when a `LoadBalancer` Service is involved

## Where to go from here

This is intentionally the smallest possible EKS setup — one self-managed worker node ASG, no Helm, no
Ingress controller, no autoscaling, no persistent storage. The companion
`ecommerce-devops-project` builds on exactly this foundation with Kubernetes manifests
organized per-microservice, ArgoCD for GitOps, and a full CI/CD pipeline that builds and
deploys on every merge.
