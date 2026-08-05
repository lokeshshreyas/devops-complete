# terraform-docker vs terraform-eks: Which One Should You Use?

> **Who this is for:** DevOps freshers who have just discovered this project has TWO Terraform modules and want to understand the difference.
>
> **Reading time:** 5 minutes

---

## The Short Answer

| If you want to… | Use |
|-----------------|-----|
| Learn DevOps basics with the smallest possible AWS footprint | **`terraform-docker/`** |
| Learn Kubernetes and container orchestration at scale | **`terraform-eks/`** |
| Get something running in 15 minutes | **`terraform-docker/`** |
| Build production-grade infrastructure | **`terraform-eks/`** (eventually) |

---

## What Each Module Does

### `terraform-docker/` — Docker Compose on a Single EC2 Instance

```
Your Browser
     │
     ▼
http://<EC2_PUBLIC_IP>
     │
┌────────────────────────────────────────────┐
│  EC2 Instance (t3.medium)                   │
│  Docker Engine                              │
│   ├── thermos-frontend  (Nginx :80)         │
│   ├── thermos-backend   (Flask :5000)       │
│   └── thermos-postgres  (PostgreSQL :5432)  │
│  All containers share one Docker network    │
└────────────────────────────────────────────┘
```

**What Terraform creates:**
1. VPC (10.0.0.0/16)
2. Public Subnet (10.0.1.0/24)
3. Internet Gateway
4. Security Group (ports 22, 80, 443, 5000)
5. EC2 Instance (t3.medium)
6. Auto-generated SSH Key Pair

**What the EC2 instance does on boot:**
1. Adds swap space (safety net)
2. Installs Docker Engine + Docker Compose plugin
3. Receives your application code from Terraform's file provisioner
4. Runs `docker compose build` and `docker compose up -d`
5. Health-checks backend and frontend

**Total AWS resources:** 7
**Total deploy time:** ~10–15 minutes
**Files in module:** `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `backend.tf`, `user_data.sh`

---

### `terraform-eks/` — Kubernetes on AWS EKS

```
Your Browser
     │
     ▼
http://<NLB_HOSTNAME>.elb.amazonaws.com
     │
┌─────────────────────────────────────────────────────────────┐
│  AWS Cloud                                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  VPC: 10.1.0.0/16                                     │  │
│  │  ┌─────────────────┐  ┌─────────────────┐             │  │
│  │  │  Public Subnet  │  │  Public Subnet  │             │  │
│  │  │  10.1.1.0/24   │  │  10.1.2.0/24   │             │  │
│  │  │                 │  │                 │             │  │
│  │  │  ┌───────────┐  │  │  ┌───────────┐  │             │  │
│  │  │  │ Worker    │  │  │  │ Worker    │  │             │  │
│  │  │  │ Node 1    │  │  │  │ Node 2    │  │             │  │
│  │  │  └───────────┘  │  │  └───────────┘  │             │  │
│  │  └─────────────────┘  └─────────────────┘             │  │
│  │           ↑                    ↑                       │  │
│  │      ┌─────────────────────────────┐                   │  │
│  │      │  EKS Control Plane          │                   │  │
│  │      │  (managed by AWS)            │                   │  │
│  │      └─────────────────────────────┘                   │  │
│  │                    ↑                                    │  │
│  │         ┌─────────────────┐                            │  │
│  │         │  NLB (Network   │                            │  │
│  │         │   Load Balancer)│                            │  │
│  │         └─────────────────┘                            │  │
│  └────────────────────┬──────────────────────────────────┘  │
│                       │                                      │
└───────────────────────┼──────────────────────────────────────┘
                        │
                   Your Browser
```

Inside each worker node, Kubernetes runs your pods:

```
Worker Node 1                    Worker Node 2
┌─────────────────────┐         ┌─────────────────────┐
│  ┌───────────────┐  │         │  ┌───────────────┐  │
│  │ postgres Pod  │  │         │  │ (empty /      │  │
│  │ :5432         │  │         │  │  spare capacity)│  │
│  └───────────────┘  │         │  └───────────────┘  │
│  ┌───────────────┐  │         └─────────────────────┘
│  │ backend Pod   │  │
│  │ :5000         │  │
│  └───────────────┘  │
│  ┌───────────────┐  │
│  │ frontend Pod  │  │
│  │ :80           │  │
│  └───────────────┘  │
└─────────────────────┘
```

**What Terraform creates:**
1. VPC (10.1.0.0/16) with 2 subnets across 2 AZs
2. Internet Gateway + NAT Gateway
3. Security Groups (cluster + node)
4. EKS Control Plane (managed by AWS)
5. IAM Roles (cluster role, node role)
6. Launch Template + Auto Scaling Group (worker nodes)
7. ECR Repositories (backend + frontend)
8. Network Load Balancer (via Kubernetes Service)

**What happens after Terraform:**
1. `03-k8s-deploy.sh` builds Docker images
2. Pushes them to ECR
3. Applies Kubernetes manifests (Secrets → Postgres → Backend → Frontend)
4. Kubernetes schedules pods across worker nodes
5. AWS NLB provisions and routes traffic

**Total AWS resources:** 15+
**Total deploy time:** ~20–30 minutes
**Files in module:** `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `backend.tf`

---

## Feature Comparison

| Feature | terraform-docker | terraform-eks |
|---------|---------------|---------------|
| **Learning curve** | Low | High |
| **Deploy time** | ~10–15 min | ~20–30 min |
| **AWS resources** | 7 | 15+ |
| **High availability** | ❌ Single EC2 = single point of failure | ✅ Multi-node, pod rescheduling |
| **Auto-scaling** | ❌ Manual only | ✅ HPA + Cluster Autoscaler |
| **Rolling updates** | ❌ Downtime during redeploy | ✅ Zero-downtime rolling deployments |
| **Load balancer** | ❌ Direct to EC2 IP | ✅ AWS Network Load Balancer |
| **Service discovery** | ❌ Hardcoded container names | ✅ Kubernetes DNS + Services |
| **Secrets management** | ❌ Plain text in docker-compose.yml | ✅ Kubernetes Secrets |
| **Storage** | Docker volume on local disk | ✅ EBS-backed Persistent Volumes |
| **Monitoring** | `docker logs` | ✅ CloudWatch + Kubernetes metrics |
| **Cost** | Lowest | Higher (EKS control plane ~$0.10/hr) |
| **KodeKloud fit** | ✅ Perfect for 3-hour session | ⚠️ Tight but doable |

---

## Directory Structure Comparison

### `terraform-docker/` (Industry-Standard Layout)

```
terraform-docker/
├── providers.tf     # Terraform version + AWS provider
├── variables.tf     # Input variables (instance_type, region, etc.)
├── main.tf          # Core resources: VPC, subnet, SG, EC2
├── outputs.tf       # Output values: EC2 IP, app URL, SSH command
├── backend.tf       # Remote state backend template (S3 + DynamoDB)
├── user_data.sh     # EC2 bootstrap script
└── README.md        # Module documentation
```

### `terraform-eks/` (Industry-Standard Layout)

```
terraform-eks/
├── providers.tf     # Terraform version + AWS provider
├── variables.tf     # Input variables (cluster_name, region, etc.)
├── main.tf          # Core resources: VPC, EKS, ASG, ECR, NLB
├── outputs.tf       # Output values: cluster name, ECR URLs
├── backend.tf       # Remote state backend template (S3 + DynamoDB)
└── README.md        # Module documentation
```

Both modules follow the **same industry-standard structure**:
- `providers.tf` — provider configuration
- `variables.tf` — all inputs in one place
- `main.tf` — resources only
- `outputs.tf` — all outputs in one place
- `backend.tf` — remote state configuration

This makes it easy to switch between modules — you already know where everything is.

---

## When to Use Which

### Use `terraform-docker/` When:

- You're a fresher or 0–2 year DevOps engineer
- You have a 3-hour KodeKloud session
- You want to learn Terraform + Docker Compose + AWS basics
- You want something working in 15 minutes
- You're building a portfolio project, not production infrastructure
- You want to understand networking (VPC, subnets, security groups) without Kubernetes abstraction

**Typical journey:**
```
Day 1: Read docs → Run 01-setup.sh → Deploy with terraform-docker/
Day 2: Test app → Monitor resources → Destroy → Redeploy
Day 3: Modify code → Validate locally → Redeploy
```

### Use `terraform-eks/` When:

- You've successfully deployed with `terraform-docker/` at least once
- You understand Docker Compose and want to learn Kubernetes
- You need to learn production patterns: auto-scaling, rolling updates, service discovery
- You have 4+ hours for a single session (or can split across sessions)
- You're preparing for a job that requires Kubernetes knowledge

**Typical journey:**
```
Week 1: Master terraform-docker/ deployment
Week 2: Read Kubernetes basics → Deploy with terraform-eks/
Week 3: Modify manifests → Test rolling updates → Add monitoring
Week 4: Explore Helm, ArgoCD, service mesh
```

---

## The Learning Path

```
┌─────────────────────────────────────────────────────────────┐
│  START HERE                                                 │
│  terraform-docker/                                          │
│  • Learn Terraform syntax                                     │
│  • Understand AWS VPC, subnets, security groups             │
│  • Practice Docker Compose                                  │
│  • Get comfortable with AWS CLI                             │
│  • Time: 1–2 days                                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  OPTIONAL: Remote State                                     │
│  scripts/advanced/01-setup-backend.sh                          │
│  • Learn S3 + DynamoDB for state management                 │
│  • Practice team collaboration patterns                     │
│  • Time: 2–3 hours                                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  NEXT LEVEL                                                 │
│  terraform-eks/                                             │
│  • Learn Kubernetes architecture                            │
│  • Practice kubectl commands                                │
│  • Understand pods, services, deployments, ingress           │
│  • Learn ECR, EBS, NLB                                    │
│  • Time: 1–2 weeks                                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ADVANCED (beyond this project)                             │
│  • Helm for package management                              │
│  • ArgoCD for GitOps                                        │
│  • Prometheus + Grafana for monitoring                      │
│  • Istio/Linkerd for service mesh                           │
│  • Time: Ongoing                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Common Questions

### "Can I skip terraform-docker and go straight to EKS?"

**Technically yes, practically no.** EKS assumes you already understand:
- VPCs, subnets, and security groups (covered in terraform-docker/)
- Docker and containerization (covered in docker-compose.yml)
- Terraform workflow (init → plan → apply → destroy)

Without these foundations, EKS error messages will be incomprehensible. Spend 1–2 days with `terraform-docker/` first.

### "Does terraform-docker use 'real' DevOps?"

**Yes.** Single-server Docker Compose is a legitimate production pattern for:
- Internal tools and dashboards
- Small SaaS applications (< 1000 users)
- Development and staging environments
- Cost-sensitive projects

Many successful companies started this way. The skills you learn (IaC, containers, networking) transfer directly to Kubernetes later.

### "Why not just use ECS instead of EKS?"

ECS is AWS's simpler container orchestrator. It's easier than EKS but less portable (AWS-only). This project uses EKS because:
1. Kubernetes skills are more transferable across employers
2. EKS is what most "DevOps Engineer" job postings ask for
3. Learning EKS teaches you concepts that apply to GKE, AKS, and on-prem clusters

ECS is a great choice for real projects, but EKS is better for learning.

### "Can I run both at the same time?"

**No.** Both modules create VPCs and AWS resources that would conflict. Choose one per KodeKloud session:

```bash
# Session 1: terraform-docker/
./scripts/03-deploy.sh
./scripts/07-destroy.sh

# Session 2: terraform-eks/
./scripts/advanced/02-eks-up.sh
./scripts/advanced/03-k8s-deploy.sh
./scripts/advanced/04-k8s-destroy.sh
```

---

## Summary

| | terraform-docker | terraform-eks |
|---|---|---|
| **Complexity** | Low | High |
| **Time** | 15 min | 30 min |
| **Cost** | Low | Higher |
| **Learning value** | Foundations | Advanced |
| **Production ready** | Small projects | Large projects |
| **Start here?** | ✅ Yes | ❌ No |

> **Rule of thumb:** If you can't explain what a VPC, subnet, and security group are, start with `terraform-docker/`. If you can draw a Kubernetes pod diagram from memory, you're ready for `terraform-eks/`.
