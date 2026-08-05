# Complete Thermos Walkthrough — From Zero to Deployed

> **Who this is for:** DevOps freshers who have never deployed to AWS before and want one document that covers **every single step** from installation to monitoring.
>
> **Total time:** 60–90 minutes
> **Prerequisites:** A KodeKloud AWS Playground session (3 hours)

---

## What You Will Build

A 3-tier web application running on a single AWS EC2 instance:

```
Your Browser
     │
     ▼
http://<EC2_PUBLIC_IP>
     │
┌────────────────────────────────────────────┐
│  EC2 Instance (t3.medium)                    │
│  ┌─────────────┐  ┌─────────────┐          │
│  │  Nginx      │  │  Flask      │          │
│  │  :80        │  │  :5000      │          │
│  │  (React UI) │  │  (API)      │          │
│  └──────┬──────┘  └──────┬──────┘          │
│         │                │                  │
│         └────────────────┘                  │
│                  │                          │
│         ┌────────┴────────┐                 │
│         │  PostgreSQL     │                 │
│         │  :5432          │                 │
│         └─────────────────┘                 │
└────────────────────────────────────────────┘
```

---

## Phase 0: Before You Start (5 minutes)

### Step 0.1: Open Your KodeKloud Playground

1. Go to [KodeKloud](https://kodekloud.com)
2. Start an **AWS Playground** session
3. Choose **us-east-1** as your region
4. Copy the **AWS Access Key ID** and **Secret Access Key** to a notepad

> ⚠️ **Important:** KodeKloud sessions expire in **3 hours**. This entire walkthrough takes about 60–90 minutes. Start the playground **only when you're ready to begin**.

### Step 0.2: Download the Project

```bash
# If you have the ZIP file:
unzip Thermos-Kubernetes-application-v11.zip
cd Thermos-Kubernetes-application

# Or clone from GitHub (if available):
# git clone <repo-url>
# cd Thermos-Kubernetes-application
```

### Step 0.3: Make Scripts Executable

```bash
chmod +x scripts/*.sh scripts/advanced/*.sh
```

---

## Phase 1: Install Tools (5–10 minutes)

### Step 1.1: Run the Setup Script

```bash
./scripts/01-setup.sh
```

**What this does:**
- Checks your operating system (Linux or macOS)
- Installs missing tools: `git`, `jq`, `aws`, `terraform`, `docker`, `kubectl`
- Skips anything already installed
- Adds your user to the `docker` group

**What you should see:**
```
================================================
 Thermos 01-setup: installing prerequisites
================================================
==> Detected OS: linux
==> Checking git
  ⏭  git already installed: git version 2.34.1
==> Checking jq
  ✅ jq installed: jq-1.6
...
================================================
 Setup summary (12s)
================================================
  ✅ git: git version 2.34.1
  ✅ terraform: Terraform v1.7.0
  ✅ aws cli: aws-cli/2.15.0
  ✅ docker: Docker version 24.0.7
  ✅ jq: jq-1.6
  ✅ kubectl: Client Version: v1.29.0
```

### Step 1.2: Configure AWS Credentials

```bash
aws configure
```

**Enter exactly what KodeKloud gave you:**
```
AWS Access Key ID [None]: AKIA... (paste from KodeKloud)
AWS Secret Access Key [None]: abc123... (paste from KodeKloud)
Default region name [None]: us-east-1
Default output format [None]: json
```

**Verify it works:**
```bash
aws sts get-caller-identity
```

**Expected output:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/kodekloud-user"
}
```

> 🎉 **Phase 1 complete!** Your machine can now talk to AWS.

---

## Phase 2: Validate Locally (10 minutes, optional but recommended)

### Step 2.1: Run Local Validation

```bash
./scripts/02-validate.sh
```

**What this does:**
1. Checks Docker is running
2. Checks all project files exist
3. Builds all three Docker images from scratch
4. Starts the full stack with Docker Compose
5. Runs health checks on each service
6. Tests the API endpoints
7. Cleans everything up

**Why do this?**
- Catches Docker/build errors **before** you waste time on AWS
- Proves the application code works
- Takes 3–8 minutes — much faster than debugging on EC2

**What you should see:**
```
================================
STEP 1/8: Checking Docker Installation
================================
✅ Docker: Docker version 24.0.7
...
================================
✅ Validation Complete!
✅ Local environment is ready for deployment.
ℹ️  Next: ./scripts/03-deploy.sh
```

> 🎉 **Phase 2 complete!** The app builds and runs locally.

---

## Phase 3: Deploy to AWS (15–20 minutes)

### Step 3.1: Run the Deploy Script

```bash
./scripts/03-deploy.sh
```

**What this does:**
1. Verifies AWS credentials
2. Runs `terraform init` (downloads AWS provider plugins)
3. Runs `terraform plan` (shows what will be created)
4. Asks you to type `yes`
5. Runs `terraform apply` (creates everything in AWS)

**What you will see:**
```
================================
Thermos 03-deploy: AWS Deployment
================================

================================
STEP 1/5: Checking Prerequisites
================================
✅ terraform found
✅ aws found
✅ git found
✅ AWS credentials OK (account 123456789012)

================================
STEP 1/4: Prerequisites
================================
...

================================
STEP 2/4: Terraform Init & Plan
================================
✅ Terraform initialized
✅ Terraform plan completed

Resources to be created:
  + aws_instance.thermos
  + aws_internet_gateway.thermos
  + aws_key_pair.thermos
  + aws_route_table.thermos
  + aws_route_table_association.public
  + aws_security_group.thermos
  + aws_subnet.public
  + aws_vpc.thermos

================================
STEP 3/4: Confirmation
================================

⚠️  This will create AWS resources in your KodeKloud AWS Playground:
  - 1 VPC (10.0.0.0/16)
  - 1 Public Subnet (10.0.1.0/24)
  - 1 Internet Gateway
  - 1 Security Group
  - 1 EC2 Instance (t3.medium)

⏰ KodeKloud sessions expire in 3 hours!

Do you want to continue? (type 'yes' to confirm): yes

================================
STEP 4/4: Creating Infrastructure
================================
✅ Infrastructure created

================================
🎉 Deployment Complete!
================================

  📍 EC2 Instance IP:  1.2.3.4
  🌐 Application URL:  http://1.2.3.4
  🔌 API URL:         http://1.2.3.4:5000/api
  🔐 SSH Command:     ssh -i terraform-docker/thermos-key.pem ubuntu@1.2.3.4
  🔑 Key File:        /home/ubuntu/Thermos/terraform-docker/thermos-key.pem
     (Keep this safe. It is required for SSH access.)

⏳ The EC2 instance is now booting and installing Docker.
   On a t3.medium this takes 1–2 minutes. DO NOT CANCEL.
```

### Step 3.2: Copy the Important Information

**Write down or screenshot:**
- EC2 Instance IP (e.g., `1.2.3.4`)
- Application URL (e.g., `http://1.2.3.4`)
- SSH Command
- Key File path

> 🎉 **Phase 3 complete!** AWS infrastructure is created. Now we wait for the software to install.

---

## Phase 4: Wait and Verify (5–10 minutes)

### Step 4.1: Understand What's Happening Right Now

Your EC2 instance is running a boot script (`user_data.sh`) that:
1. ✅ Adds 2 GB swap space (prevents out-of-memory crashes)
2. ✅ Updates system packages
3. ✅ Installs Docker Engine
4. ✅ Waits for Terraform to upload your application files
5. ⏳ **Building Docker images** ← You are here (takes 1–2 minutes)
6. Starts containers
7. Runs health checks

**Why does this take so long?**
- The `t3.medium` has only 4 GB RAM
- Building the React frontend requires Node.js + npm
- npm install is memory-intensive
- The swap space prevents crashes, but builds are still slow
- **This is completely normal — do not cancel**

### Step 4.2: Run the Verification Script

```bash
./scripts/04-verify.sh
```

**What this does:**
- Polls your EC2 instance every 15 seconds
- Checks if the frontend (port 80) responds
- Checks if the backend (port 5000) responds
- Retries up to 40 times (10 minutes total)

**What you should see:**
```
================================
Thermos 04-verify: Deployment Verification
================================

ℹ️  Target instance: 1.2.3.4
ℹ️  Frontend: http://1.2.3.4/
ℹ️  Backend health: http://1.2.3.4:5000/health
ℹ️  Max wait time: 10 minutes (40 attempts x 15s)

Attempt 1/40: frontend=waiting, backend=waiting
Attempt 2/40: frontend=waiting, backend=waiting
...
Attempt 18/40: BOTH RESPONDING 🎉

✅ Frontend is responding: http://1.2.3.4/
✅ Backend health check passed: http://1.2.3.4:5000/health

✅ Deployment verified! Open http://1.2.3.4/ in your browser.
```

**If it times out:**
```bash
# SSH in and check what's happening
./scripts/06-ssh.sh
cat /var/tmp/thermos-setup.log
docker compose ps
docker compose logs -f
```

See [13-checking-and-monitoring.md](13-checking-and-monitoring.md) for detailed troubleshooting.

> 🎉 **Phase 4 complete!** Your application is live.

---

## Phase 5: Test the Application (10 minutes)

### Step 5.1: Open in Browser

Go to: `http://<YOUR_EC2_IP>`

Example: `http://1.2.3.4`

### Step 5.2: Register an Account

1. Click "Register"
2. Enter any username, email, and password
3. Click "Register"

### Step 5.3: Log In

1. Enter your username and password
2. Click "Login"

### Step 5.4: Add a Bookmark

1. Enter a URL (e.g., `https://github.com`)
2. Enter a title (e.g., `GitHub`)
3. Enter tags (e.g., `devops, code`)
4. Click "Add Bookmark"

### Step 5.5: Verify It Saved

The bookmark should appear in your dashboard. Refresh the page — it should still be there.

> 🎉 **Phase 5 complete!** The application is fully functional.

---

## Phase 6: Monitor Your Resources (Ongoing)

### Step 6.1: Quick Status Check

```bash
./scripts/05-status.sh
```

Shows:
- Local Docker containers (should be empty if you cleaned up)
- AWS EC2 instances (should show your running instance)
- Terraform state (should show tracked resources)

### Step 6.2: Check AWS Resources Manually

```bash
# See your EC2 instance
aws ec2 describe-instances --filters "Name=tag:Project,Values=thermos" --output table

# See your security group rules
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=thermos-sg" --output table

# See your VPC
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=thermos-vpc" --output table
```

### Step 6.3: SSH Into the Server

```bash
./scripts/06-ssh.sh
```

**What you can do inside:**
```bash
# View boot log
cat /var/tmp/thermos-setup.log

# Watch live logs
tail -f /var/tmp/thermos-setup.log

# Check running containers
docker compose ps

# Check container logs
docker compose logs -f

# Check system resources
free -h    # Memory and swap
htop       # CPU and processes (press q to quit)
df -h      # Disk space

# Restart a service
docker compose restart thermos-backend

# Exit SSH
exit
```

### Step 6.4: Check Application Health Endpoints

```bash
# From your local machine:
curl http://<EC2_IP>:5000/health

# Should return:
{"status": "healthy", "service": "thermos-backend"}
```

### Step 6.5: Monitor During Your Session

**Every 30 minutes, run:**
```bash
./scripts/05-status.sh
```

**Before your KodeKloud session ends, run:**
```bash
./scripts/07-destroy.sh
```

> 🎉 **Phase 6 complete!** You know how to monitor everything.

---

## Phase 7: Clean Up (5 minutes)

### Step 7.1: Destroy Everything

```bash
./scripts/07-destroy.sh
```

**What this does:**
1. Runs `terraform destroy` (deletes EC2, VPC, security group, etc.)
2. Removes local Terraform state files
3. Cleans up local Docker containers/images from validation

**What you should see:**
```
================================
Thermos 07-destroy: Full Teardown
================================

================================
Destroying AWS Infrastructure
================================
⚠️  This will DESTROY all AWS resources created by this project:
  - EC2 Instance
  - VPC, Subnet, Internet Gateway
  - Security Group
  - SSH Key Pair

Type 'yes' to confirm destruction: yes
✅ AWS infrastructure destroyed

================================
Cleaning Local State Files
================================
✅ Local state files removed

================================
Cleaning Local Docker Resources
================================
✅ Local containers stopped
✅ Local Docker cleanup complete

================================
Teardown Complete
================================
✓ AWS infrastructure destroyed
✓ Local Docker resources cleaned
✓ Local Terraform state cleaned
```

### Step 7.2: Verify Cleanup

```bash
./scripts/05-status.sh
```

**Should show:**
```
✅ No local containers running (clean)
✅ No EC2 instances tagged 'Project=thermos' found in AWS
✅ Terraform state is empty
```

> 🎉 **Phase 7 complete!** Everything is cleaned up. Your KodeKloud session is safe.

---

## Complete Command Reference

| Phase | Command | What It Does |
|-------|---------|-------------|
| 1 | `./scripts/01-setup.sh` | Install all tools |
| 1 | `aws configure` | Set up AWS credentials |
| 2 | `./scripts/02-validate.sh` | Test locally with Docker Compose |
| 3 | `./scripts/03-deploy.sh` | Deploy to AWS EC2 |
| 4 | `./scripts/04-verify.sh` | Poll until app responds |
| 5 | Open `http://<EC2_IP>` | Test in browser |
| 6 | `./scripts/05-status.sh` | Check local + AWS status |
| 6 | `./scripts/06-ssh.sh` | SSH into EC2 instance |
| 7 | `./scripts/07-destroy.sh` | Tear down everything |

### Common Flags

```bash
# Skip local validation (faster deploy):
./scripts/03-deploy.sh

# Auto-confirm without typing 'yes':
./scripts/03-deploy.sh -y

# Fastest path:
./scripts/03-deploy.sh -y 

# Only destroy AWS, keep local Docker:
./scripts/07-destroy.sh --aws-only

# Only clean local Docker, keep AWS:
./scripts/07-destroy.sh --local-only
```

---

## What If Something Goes Wrong?

### The Deploy Script Fails

1. Read the error message carefully
2. Check [07-troubleshooting.md](07-troubleshooting.md)
3. Run `./scripts/05-status.sh` to see what's actually running
4. Run `./scripts/07-destroy.sh` and try again

### The App Doesn't Respond After 10 Minutes

1. SSH in: `./scripts/06-ssh.sh`
2. Check boot log: `cat /var/tmp/thermos-setup.log`
3. Check containers: `docker compose ps`
4. Check logs: `docker compose logs -f`
5. See [13-checking-and-monitoring.md](13-checking-and-monitoring.md) for detailed debugging

### I Forgot to Destroy Before My Session Ended

- KodeKloud automatically cleans up playground resources when your session expires
- But it's good practice to always run `./scripts/07-destroy.sh`

---

## Level 2: EKS Deployment (Optional, 30–40 minutes)

> **Only do this after completing the EC2 deployment above and understanding it.**
> EKS is more complex, costs more, and takes longer. It's worth it for learning
> Kubernetes, but don't start here.

### EKS Prerequisites

- You have completed the EC2 deployment at least once
- You understand the difference between Docker Compose and Kubernetes
- You have 40+ minutes remaining in your KodeKloud session

### EKS Deploy Steps

```bash
# STEP 1: Create the EKS cluster (~10-15 minutes)
./scripts/advanced/02-eks-up.sh

# STEP 2: Deploy the application (~5-10 minutes)
./scripts/advanced/03-k8s-deploy.sh

# STEP 3: WAIT — the script will poll for you, but total time
#         from cluster creation to browser-accessible URL is 20-30 minutes
```

### What `02-eks-up.sh` Does

1. Checks/creates required IAM roles (`eksClusterRole`, `AmazonEKSNodeRole`)
2. Runs `terraform apply` in `terraform-eks/`
3. Creates: VPC (10.1.0.0/16), 2 subnets, EKS cluster, worker node ASG, ECR repos

**What you should see when it finishes:**
```
✅ EKS cluster is ACTIVE
✅ Worker node ASG created
Configure kubectl: aws eks update-kubeconfig --name thermos-eks --region us-east-1
```

### What `03-k8s-deploy.sh` Does

1. Builds Docker images from `src/backend/Dockerfile` and `src/frontend/Dockerfile`
2. Pushes them to the ECR repos Terraform created
3. Configures `kubectl` to talk to your cluster
4. Waits for worker nodes to become `Ready`
5. Applies Kubernetes manifests in order: Secrets → Postgres → Backend → Frontend
6. Waits for each Deployment rollout to complete
7. Waits for the LoadBalancer hostname to be assigned
8. **Polls the URL until it actually responds** (this is the slow part)

**What you should see when it finishes:**
```
✅ APPLICATION IS ACCESSIBLE!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🌐 Application URL:  http://a1b2c3d4...elb.amazonaws.com/
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

> ⚠️ **If the script says the URL is accessible but your browser doesn't load it yet,**
> wait 1–2 more minutes for DNS to propagate, then refresh.

### Verify EKS Deployment

```bash
# Check pods are running
kubectl get pods

# Check the LoadBalancer service
kubectl get svc thermos-frontend

# Check node status
kubectl get nodes

# Watch backend logs
kubectl logs -f deploy/thermos-backend
```

### EKS Tear Down

```bash
./scripts/advanced/04-k8s-destroy.sh
```

This deletes Kubernetes resources first (including the LoadBalancer Service so AWS releases the ELB), then destroys the EKS cluster, worker nodes, VPC, and ECR repos.

> ⚠️ **Always use `04-k8s-destroy.sh`, not `terraform destroy` directly.** Order matters when a LoadBalancer Service exists.

---

## What's Next?

After completing this walkthrough, you can explore:

| Level | What | Documentation |
|-------|------|--------------|
| Level 1 (you just did this) | Single EC2 + Docker Compose | This document + RUNBOOK.md |
| Level 2 (optional) | Kubernetes on EKS | [11-kubernetes-eks-optional.md](11-kubernetes-eks-optional.md) |
| Level 2 | Remote Terraform state (S3 + DynamoDB) | [09-remote-terraform-state.md](09-remote-terraform-state.md) |
| Level 2 | CI/CD pipeline | [10-cicd-pipeline.md](10-cicd-pipeline.md) |

---

**You did it! 🎉** You have successfully deployed a full 3-tier application to AWS using Terraform and Docker Compose.
