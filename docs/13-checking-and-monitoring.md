# Checking, Verifying, and Monitoring Your Thermos Resources

> **Who this is for:** DevOps freshers who have just deployed (or are about to deploy) Thermos and want to know **"How do I check if everything is working?"**
>
> **How long to read:** 10 minutes
> **How long to practice:** 15–20 minutes

---

## Table of Contents

1. [Quick Health Check (30 seconds)](#1-quick-health-check-30-seconds)
2. [Checking Local Resources](#2-checking-local-resources)
3. [Checking AWS Resources](#3-checking-aws-resources)
4. [Checking Application Health](#4-checking-application-health)
5. [Monitoring Live Logs](#5-monitoring-live-logs)
6. [Troubleshooting Dashboard](#6-troubleshooting-dashboard)
7. [What to Watch During Deployment](#7-what-to-watch-during-deployment)

---

## 1. Quick Health Check (30 seconds)

Run this **one command** to see everything at a glance:

```bash
./scripts/05-status.sh
```

This shows you:
- **Local:** Are any Docker containers still running on your laptop?
- **AWS:** Are there any EC2 instances tagged `Project=thermos`?
- **Terraform:** Is there state tracking any resources?

**Example output when everything is clean:**

```
================================
LOCAL Docker Status
================================
✅ No local containers running (clean)

================================
AWS EC2 Status (queried directly from AWS)
================================
✅ No EC2 instances tagged 'Project=thermos' found in AWS

================================
Terraform State
================================
✅ Using local Terraform state
✅ Terraform has not been initialized yet
```

**Example output when something is deployed:**

```
================================
AWS EC2 Status (queried directly from AWS)
================================
------------------------------------------
|           DescribeInstances            |
+----------+--------+-----------+----------+
|    ID    | State  |    IP     |  Type    |
+----------+--------+-----------+----------+
| i-abc123 | running| 1.2.3.4   | t3.medium |
+----------+--------+-----------+----------+
```

> **💡 Pro Tip:** Run this command **before** you start (to confirm a clean slate) and **after** you finish (to confirm cleanup worked).

---

## 2. Checking Local Resources

These commands work on your own machine (laptop or the KodeKloud playground terminal).

### 2.1 Are Docker containers running locally?

```bash
docker ps
```

**What you should see:**
- **Before deploy:** Empty list (or unrelated containers)
- **During `02-validate.sh`:** Three containers: `thermos-postgres`, `thermos-backend`, `thermos-frontend`
- **After cleanup:** Empty list

**What the columns mean:**

| Column | What it tells you |
|--------|-------------------|
| `CONTAINER ID` | Short unique ID of the container |
| `IMAGE` | Which Docker image is running |
| `STATUS` | `Up 5 minutes` = healthy; `Exited` = stopped; `Restarting` = crashing |
| `PORTS` | Which ports are exposed (e.g., `0.0.0.0:80->80/tcp`) |
| `NAMES` | Human-readable name (e.g., `thermos-backend`) |

### 2.2 Check Docker Compose status specifically

```bash
cd /path/to/Thermos
docker compose ps
```

This only shows Thermos containers (not other projects).

### 2.3 Check if Docker images exist locally

```bash
docker images | grep thermos
```

Shows the built images. If you ran `02-validate.sh`, you'll see images for the frontend, backend, and postgres.

### 2.4 Check Docker disk usage

```bash
docker system df
```

Shows how much disk space Docker is using. If this is high, run `docker system prune` to clean up.

### 2.5 Check Docker logs for a specific container

```bash
docker logs thermos-backend
docker logs thermos-postgres
docker logs thermos-frontend
```

Add `-f` to "follow" (watch live):
```bash
docker logs -f thermos-backend
```

Press `Ctrl+C` to stop following.

---

## 3. Checking AWS Resources

These commands check what actually exists in your AWS account (the KodeKloud playground).

### 3.1 Check EC2 Instances

```bash
aws ec2 describe-instances --filters "Name=tag:Project,Values=thermos" --output table
```

**What to look for:**

| Field | Healthy | Problem |
|-------|---------|---------|
| `State` | `running` | `pending` (still booting), `stopped` (crashed), `terminated` (destroyed) |
| `IP` | Has a public IP | Empty = no internet access |
| `Type` | `t3.medium` or your chosen type | Wrong type = cost or performance issue |
| `Launch` | Recent timestamp | Very old = forgot to destroy |

### 3.2 Check Security Groups (Firewall Rules)

```bash
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=thermos-sg" --output table
```

**What to verify:**
- Port 22 (SSH) is open from your IP
- Port 80 (HTTP) is open from anywhere
- Port 5000 (API) is open from anywhere
- Port 443 (HTTPS) is open (reserved for future)

### 3.3 Check VPC and Subnet

```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=thermos-vpc" --output table
aws ec2 describe-subnets --filters "Name=tag:Name,Values=thermos-public-subnet" --output table
```

### 3.4 Check Internet Gateway

```bash
aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=thermos-igw" --output table
```

**Why this matters:** Without the Internet Gateway, your EC2 instance cannot download Docker images or receive traffic from the internet.

### 3.5 Check Key Pairs

```bash
aws ec2 describe-key-pairs --key-names thermos-key-
```

> Note: The suffix is random, so use the AWS Console or list all key pairs:
> ```bash
> aws ec2 describe-key-pairs --query 'KeyPairs[?contains(KeyName, `thermos`)]' --output table
> ```

### 3.6 Check EKS Cluster (Level 2 only)

```bash
aws eks list-clusters
aws eks describe-cluster --name thermos-eks --output table
```

### 3.7 Check EKS Node Group / Auto Scaling Group

```bash
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `thermos`)]' --output table
```

---

## 4. Checking Application Health

These commands check if the Thermos **application itself** is working.

### 4.1 Check Backend Health Endpoint

```bash
curl http://<EC2_IP>:5000/health
```

**Expected response:**
```json
{"status": "healthy", "service": "thermos-backend"}
```

**Bad responses:**
- `Connection refused` = backend is not running
- `502 Bad Gateway` = Nginx can't reach backend
- Timeout = backend is starting up (wait longer)

### 4.2 Check Frontend

```bash
curl -I http://<EC2_IP>/
```

**Expected:** `HTTP/1.1 200 OK`

**Bad responses:**
- `Connection refused` = frontend container not running
- `502` = Nginx error (check backend)
- No response = security group blocking port 80

### 4.3 Test User Registration (API)

```bash
curl -X POST http://<EC2_IP>:5000/api/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@test.com","password":"test123"}'
```

**Expected:** `{"message":"User created successfully"}` or similar JSON

### 4.4 Test Login (API)

```bash
curl -X POST http://<EC2_IP>:5000/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test123"}'
```

**Expected:** JSON with a `token` field

### 4.5 Test Database Connectivity (from inside the instance)

```bash
./scripts/06-ssh.sh
docker compose exec postgres pg_isready -U thermos
```

**Expected:** `/var/run/postgresql:5432 - accepting connections`

---

## 5. Monitoring Live Logs

### 5.1 Watch EC2 Boot Logs (Most Important During First Deploy)

```bash
./scripts/06-ssh.sh
cat /var/tmp/thermos-setup.log
```

**What you'll see:**
- Step 0/7: Swap space added
- Step 1/7: System packages updated
- Step 2/7: Docker installed
- Step 3/7: Docker permissions configured
- Step 4/7: Waiting for application files...
- Step 5/7: Building images (this takes 1–2 minutes on t3.medium)
- Step 6/7: Verifying containers
- Step 7/7: Health checks

**Watch live:**
```bash
tail -f /var/tmp/thermos-setup.log
```

Press `Ctrl+C` to stop.

### 5.2 Watch Docker Compose Logs

```bash
./scripts/06-ssh.sh
cd /home/ubuntu/thermos
docker compose logs -f
```

This shows logs from **all three** containers interleaved. To see just one:

```bash
docker compose logs -f thermos-backend
docker compose logs -f thermos-frontend
docker compose logs -f thermos-postgres
```

### 5.3 Watch System Resources

```bash
./scripts/06-ssh.sh
htop
```

Shows CPU, memory, and swap usage in real time. Press `q` to quit.

**What to watch:**
- **Memory:** Should stay below 1 GB (with swap covering the rest)
- **Swap:** Will be used heavily during `npm run build` — this is normal
- **CPU:** Will spike during Docker builds — this is normal

### 5.4 Check Disk Space

```bash
./scripts/06-ssh.sh
df -h
```

**What to watch:** The root partition (`/`) should have at least 2 GB free. If it's full, Docker builds will fail.

---

## 6. Troubleshooting Dashboard

| Symptom | How to Check | Likely Cause | Fix |
|---------|-----------|--------------|-----|
| `terraform apply` fails | Read error message | AWS credentials expired | Re-run `aws configure` |
| EC2 instance shows `pending` for >10 min | `aws ec2 describe-instances` | AWS capacity issue | Terminate and retry |
| `04-verify.sh` times out | `tail -f /var/tmp/thermos-setup.log` | Build still running | Wait longer (up to 10 min) |
| Backend health check fails | `docker compose logs thermos-backend` | Database not ready | Wait for postgres healthcheck |
| Frontend loads but API fails | Browser DevTools → Network tab | CORS or wrong API URL | Check `docker-compose.yml` has no `REACT_APP_API_URL` |
| `Permission denied (publickey)` | Check key file exists and is 600 | Wrong key path or permissions | Run `./scripts/06-ssh.sh` |
| `502 Bad Gateway` | `docker compose ps` | Backend container down | Check backend logs |
| `Out of memory` in logs | `dmesg \| tail -20` | t3.medium RAM exhausted | Swap is now added in v11 — re-deploy |
| Can't find EC2 in AWS | `aws ec2 describe-instances` with no filter | Instance in different region | Check `aws configure get region` |

---

## 7. What to Watch During Deployment

### Timeline of a Typical Deploy (t3.medium)

| Time | What Happens | What You Should See |
|------|-------------|---------------------|
| 0:00 | Run `./scripts/03-deploy.sh` | Terraform plan output |
| 0:02 | Type `yes` | Terraform starts creating resources |
| 0:03 | VPC, subnet, security group created | Green checkmarks in output |
| 0:04 | EC2 instance launches | `aws_instance.thermos: Creation complete` |
| 0:05 | Files uploaded via Terraform | `local-exec` success message |
| 0:05 | `user_data.sh` starts running | Nothing visible yet — SSH in to watch |
| 0:06 | Swap added, packages updating | `cat /var/tmp/thermos-setup.log` |
| 0:08 | Docker installing | Log shows `Docker installed successfully` |
| 0:10 | Docker Compose build starts | Log shows `Building images...` |
| 0:13 | npm install running (memory-heavy) | `htop` shows high swap usage |
| 0:15 | React build completes | Log shows `Containers started` |
| 0:16 | Health checks run | Log shows `✓ Backend is healthy` |
| 0:17 | Run `./scripts/04-verify.sh` | `✅ Deployment verified!` |

### Commands to Run in Parallel During Deploy

**Terminal 1:** Run the deploy
```bash
./scripts/03-deploy.sh
```

**Terminal 2:** (After EC2 IP appears) SSH in immediately
```bash
./scripts/06-ssh.sh
tail -f /var/tmp/thermos-setup.log
```

**Terminal 3:** Watch AWS instance status
```bash
watch -n 5 'aws ec2 describe-instances --filters "Name=tag:Project,Values=thermos" --query "Reservations[*].Instances[*].State.Name" --output text'
```

---

## 8. Checking EKS Resources (Level 2)

### 8.1 Check EKS Cluster Status

```bash
aws eks describe-cluster --name thermos-eks --output table
```

**What to look for:**

| Field | Healthy | Problem |
|-------|---------|---------|
| `Status` | `ACTIVE` | `CREATING` (still provisioning), `FAILED` |
| `Endpoint` | Has a URL | Empty = control plane not ready |
| `RoleArn` | Contains `eksClusterRole` | Wrong role = IAM permission issue |

### 8.2 Check Worker Nodes

```bash
kubectl get nodes
```

**Expected:**
```
NAME                                          STATUS   ROLES    AGE
ip-10-1-0-123.us-east-1.compute.internal     Ready    <none>   5m
```

**If STATUS is `NotReady`:**
```bash
kubectl describe node <node-name>
# Check Events: at the bottom for why it can't join
```

### 8.3 Check All Pods

```bash
kubectl get pods -o wide
```

**Expected (3 pods, all Running):**
```
NAME                                READY   STATUS    RESTARTS
postgres-xxx                        1/1     Running   0
thermos-backend-xxx                 1/1     Running   0
thermos-frontend-xxx                1/1     Running   0
```

**Common bad statuses:**

| Status | Meaning | Fix |
|--------|---------|-----|
| `Pending` | No node ready or resource limits hit | Wait for node, or check `kubectl describe pod` |
| `ImagePullBackOff` | Can't pull image from ECR | Re-run `03-k8s-deploy.sh` to push images |
| `CrashLoopBackOff` | Container keeps crashing | `kubectl logs` to see why |
| `FailedScheduling` | No node has enough resources | Check node capacity with `kubectl describe node` |

### 8.4 Check LoadBalancer Service

```bash
kubectl get svc thermos-frontend
```

**Expected:**
```
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP
thermos-frontend   LoadBalancer   10.100.1.2      a1b2c3d4...elb.amazonaws.com
```

**If EXTERNAL-IP stays `<pending>` for >5 minutes:**
```bash
# Check why
kubectl describe svc thermos-frontend
# Look at Events: for errors about subnet tags or IAM permissions

# Check subnet tags (must have kubernetes.io/cluster/thermos-eks = shared)
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/cluster/thermos-eks,Values=shared" \
  --query 'Subnets[*].SubnetId' --output table
```

### 8.5 Test the LoadBalancer URL

```bash
# Get the URL
LB_URL=$(kubectl get svc thermos-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -I http://${LB_URL}/
```

**If `curl` hangs or returns connection refused:**
- The NLB is still provisioning (normal, wait 3-5 more minutes)
- The NLB health checks are failing (check `kubectl describe svc`)
- DNS hasn't propagated yet (wait 2-5 more minutes)

### 8.6 Check NLB Target Health (AWS Console)

1. Open AWS Console → EC2 → Load Balancers
2. Find the NLB named `k8s-...-thermos-frontend-...`
3. Click "Target groups" → Select the target group → "Targets" tab
4. Check if targets show as `healthy`

**If targets are `unhealthy`:**
- Pods aren't ready yet (wait)
- Security group is blocking NodePort range (30000-32767)
- Subnet routing is wrong

### 8.7 Watch Live Logs

```bash
# All pods
kubectl logs -f --all-containers --prefix

# Specific pod
kubectl logs -f deploy/thermos-backend
kubectl logs -f deploy/thermos-frontend
kubectl logs -f deploy/postgres

# Previous container (if it crashed)
kubectl logs -f deploy/thermos-backend --previous
```

### 8.8 Check Cluster Events

```bash
kubectl get events --sort-by=.lastTimestamp
```

**What to look for:**
- `FailedScheduling` = resource or node issue
- `FailedMount` = volume issue
- `ImagePullBackOff` = ECR auth or image missing
- `Unhealthy` = readiness probe failing

### 8.9 EKS Timing Reference

| Milestone | Typical Time | What to Check |
|-----------|-------------|---------------|
| `02-eks-up.sh` starts | 0:00 | Terraform plan output |
| EKS cluster ACTIVE | 10-15 min | `aws eks describe-cluster` |
| Worker node Ready | 1-2 min after cluster | `kubectl get nodes` |
| Images built & pushed | 2-5 min | `03-k8s-deploy.sh` output |
| Pods Running | 1-2 min after apply | `kubectl get pods` |
| LoadBalancer hostname | 2-3 min after Service | `kubectl get svc` |
| **URL responds** | **3-8 min after hostname** | `curl http://<hostname>/` |
| **Total** | **20-30 min** | Be patient |

---

## Summary Cheat Sheet

| I want to... | Run this |
|-------------|----------|
| See everything at once | `./scripts/05-status.sh` |
| Check if app is responding | `./scripts/04-verify.sh` |
| SSH into the server | `./scripts/06-ssh.sh` |
| Watch live boot logs | `tail -f /var/tmp/thermos-setup.log` |
| Watch Docker logs | `docker compose logs -f` |
| Check AWS resources | `aws ec2 describe-instances --filters "Name=tag:Project,Values=thermos"` |
| Check backend health | `curl http://<IP>:5000/health` |
| Check frontend | `curl -I http://<IP>/` |
| Check system resources | `htop` or `free -h` |
| Clean everything up | `./scripts/07-destroy.sh` |

---

**Next:** See [14-complete-walkthrough.md](14-complete-walkthrough.md) for the full step-by-step master guide.
