# 7. Troubleshooting

## Docker Compose won't start

```bash
docker ps                    # is the daemon even running?
docker system prune -a       # clean up dangling images/containers
docker compose down
docker compose up -d
```

If the daemon itself won't start, see [04-prerequisites-and-tools.md](04-prerequisites-and-tools.md#docker-daemon-not-running).

## Database connectivity — backend can't reach Postgres

```bash
docker compose logs thermos-backend       # look for connection refused / auth errors

sleep 10                                  # Postgres init can take a few seconds on first boot

docker compose exec -T postgres psql -U thermos -d thermos -c "SELECT 1"
```

If the `SELECT 1` fails, Postgres itself isn't healthy yet — check
`docker compose logs thermos-postgres` for its own startup errors (disk space, permission
issues on the mounted volume, etc.).

## Terraform apply fails

```bash
cd terraform-docker
ls -la main.tf user_data.sh        # confirm both files are present

aws sts get-caller-identity        # confirm credentials are still valid

terraform apply tfplan             # re-run; Terraform is idempotent
```

Common causes on KodeKloud specifically:

- **Credentials expired** — playground sessions have a fixed lifetime; re-copy fresh
  credentials with `aws configure` if the session was renewed.
- **Instance type not permitted** — double-check `instance_type` in `main.tf` is still
  `t3.medium` and hasn't been edited to something the playground blocks (see
  [03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md)).
- **Resource limit hit** — if you have another Thermos deployment still running from an
  earlier session, destroy it first (`./scripts/07-destroy.sh`) before creating a new one.

## Can't SSH into the EC2 instance

```bash
chmod 600 ~/.ssh/<your-key>.pem     # SSH refuses keys with loose permissions

aws ec2 describe-instances          # confirm the instance is actually "running"

sleep 60                            # it may still be booting
./scripts/06-ssh.sh            # or: ssh -i <key.pem> ubuntu@<IP>
```

If the security group somehow doesn't allow port 22 (it should by default — see
`terraform-docker/main.tf`), re-check `terraform plan` output for unexpected drift.

## Application shows a 502 error

The frontend (Nginx) is up but the backend isn't responding yet.

```bash
# From inside the instance, or via 06-ssh.sh:
docker compose exec thermos-frontend curl http://backend:5000/health
docker compose logs thermos-frontend
docker compose logs thermos-backend
docker compose restart thermos-backend
```

Backends usually just need a few more seconds after the frontend is already serving — Flask
waits on the database health check before it's fully ready.

## "Application files did not arrive" during EC2 boot

Since v2, Terraform uploads your code directly (no GitHub involved — see
[06-terraform-deployment.md](06-terraform-deployment.md)). If `user_data.sh`'s wait loop
times out with this message, the `file` provisioner in `main.tf` likely never completed
during `terraform apply`.

```bash
# Look at the actual 'terraform apply' output on your own machine first - the file
# provisioner logs directly to your terminal, e.g.:
#   aws_instance.thermos: Provisioning with 'file'...

# If it already finished, SSH in and check what arrived:
./scripts/06-ssh.sh
ls -la /home/ubuntu/thermos
cat /var/tmp/thermos-setup.log
```

Common causes:

- **Security group didn't allow port 22 from wherever you ran `terraform apply`** — check
  `allowed_ssh_cidr` in `main.tf` hasn't been tightened to something that excludes your own
  machine.
- **`terraform apply` was interrupted** (Ctrl+C, lost connection) before the file
  provisioners finished — just re-run `terraform apply`; Terraform will retry the
  provisioners.
- **Instance took unusually long to boot sshd** — the provisioner connection has a 5-minute
  timeout; on a slow KodeKloud session this is rarely hit, but re-running `apply` is safe if
  it does.

## "InvalidKeyPair.Duplicate" on `terraform apply`

This means an EC2 key pair with the same name already exists in your AWS account — usually
from an earlier session where cleanup didn't fully finish. `main.tf` appends a random suffix
to the key pair name specifically to avoid this, but if you still hit it:

```bash
aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName'
aws ec2 delete-key-pair --key-name <the-stale-name>
```

Then re-run `terraform apply`.

## EKS (Level 2) — `eks:CreateNodegroup` AccessDeniedException

```
AccessDeniedException: User: .../kk_labs_user_xxxxxx is not authorized to perform:
eks:CreateNodegroup on resource: ... because no identity-based policy allows the
eks:CreateNodegroup action
```

This isn't a bug in this project — the KodeKloud AWS Playground has an explicit IAM deny on
managed EKS node groups for every account, confirmed by KodeKloud staff. That's exactly why
`terraform-eks/main.tf` doesn't use `aws_eks_node_group` at all; it uses a self-managed
Launch Template + Auto Scaling Group instead. If you're seeing this, you're likely running
an older copy of `main.tf` — pull the current version. See
[03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md#eks-node-groups-are-blocked-in-the-playground)
for the full explanation.

## EKS (Level 2) — `terraform apply` wants to replace the whole cluster

```
# aws_eks_cluster.thermos must be replaced
~ access_config {
    - bootstrap_cluster_creator_admin_permissions = true -> null # forces replacement
  }
```

Only happens if you hand-edit the `access_config` block on a cluster that already exists.
`bootstrap_cluster_creator_admin_permissions` is a ForceNew field — leaving it unset when it
differs from the cluster's real value forces a destroy+recreate. `terraform-eks/main.tf`
already sets it explicitly (`= true`) to match AWS's default, so a plain `terraform apply`
shouldn't trigger this. If you do see it, run `terraform plan` and make sure that field is
present and set to `true` in your `access_config` block before applying.

## EKS (Level 2) — SSM parameter "couldn't find resource" for the node AMI

```
Error: reading SSM Parameter (/aws/service/eks/optimized-ami/1.36/amazon-linux-2/recommended/image_id):
couldn't find resource
```

AWS stopped publishing new Amazon Linux 2 EKS-optimized AMIs once Amazon Linux 2023 became
the default — that SSM path simply doesn't exist for recent Kubernetes versions.
`terraform-eks/main.tf` already points at the `amazon-linux-2023` SSM path and uses AL2023's
`nodeadm` YAML `NodeConfig` bootstrap format instead of the old `bootstrap.sh`. If you see
this error, check `data "aws_ssm_parameter" "eks_ami"` in `main.tf` still says
`amazon-linux-2023`, not `amazon-linux-2`.

## EKS (Level 2) — node never joins the cluster (`kubectl get nodes` shows nothing)

```bash
aws eks update-kubeconfig --name thermos-eks --region us-east-1
kubectl get nodes -o wide     # can take 2-4 minutes after the ASG instance boots
```

If it's still empty after ~5 minutes:

```bash
# Find the instance the ASG launched
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names thermos-eks-nodes \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' --output text

# Check its boot/bootstrap logs
aws ec2 get-console-output --instance-id <instance-id> --output text | tail -50
```

Most likely causes: the launch template's `user_data` NodeConfig YAML doesn't match the
cluster's actual endpoint/CA (stale state after editing `main.tf` — re-run `terraform apply`
so the launch template picks up fresh values), or a security-group/subnet routing issue
blocking the node from reaching the cluster's API server.

## EKS (Level 2) — `thermos-frontend` Service stuck at `EXTERNAL-IP: <pending>`

```bash
kubectl get svc thermos-frontend
# NAME               TYPE           EXTERNAL-IP   PORT(S)
# thermos-frontend   LoadBalancer   <pending>     80:xxxxx/TCP
```

**Most likely cause (confirmed): the Service is missing the NLB annotation, so it's
defaulting to a Classic Load Balancer, which the KodeKloud AWS Playground has a confirmed
deny on.** KodeKloud staff stated this directly on their community forum: *"The playground
does not have permissions to create classic load balancers. You should however be able to
create an application or network load balancer."* This deny happens silently deep inside
AWS's own reconciler — nothing in `terraform apply`, `kubectl apply`, or normal `kubectl`
output calls it out. If you waited 15-20+ minutes after a clean `terraform apply` with
`EXTERNAL-IP` never changing, this is almost certainly it.

`kubernetes/03-frontend.yaml` already carries the fix:
```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```
If you're on an older copy of this file, pull the current version and re-apply just the
frontend manifest (no need to redeploy everything):
```bash
kubectl apply -f kubernetes/03-frontend.yaml
kubectl get svc thermos-frontend --watch
```
Full explanation:
[12-eks-architecture-and-networking.md §4.3](12-eks-architecture-and-networking.md#43-the-real-confirmed-blocker--classic-elb-is-denied-in-the-playground).

**Second possible cause:** the public subnets or worker node instances aren't tagged with
the cluster's exact name (`kubernetes.io/cluster/thermos-eks`), which is what AWS uses to
auto-discover which subnets it's allowed to place a Load Balancer in. `terraform-eks/main.tf`
already sets this correctly — see
[12-eks-architecture-and-networking.md §4.4](12-eks-architecture-and-networking.md#44-a-second-smaller-bug-also-found-and-fixed--subnetcluster-name-tag-mismatch)
for the full explanation. If you're on an older copy of `main.tf`, pull the current version
and re-run `terraform apply` (tag-only change, nothing gets destroyed).

If both of the above are already correct and it's still pending after a few minutes:

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
aws elbv2 describe-target-health --target-group-arn <arn-from-describe-target-groups>
kubectl describe svc thermos-frontend    # check the Events section for provisioning errors
```

## General diagnostic commands

```bash
./scripts/05-status.sh                 # local + AWS state at a glance
./scripts/04-verify.sh      # is the deployed app actually responding?
terraform show                      # (from terraform-docker/) full current state
docker compose ps                   # local or on the instance: what's running right now
```

## Still stuck?

- Terraform docs: https://www.terraform.io/docs
- AWS CLI docs: https://aws.amazon.com/cli/
- Docker docs: https://docs.docker.com/
- KodeKloud playground help: bottom-right help widget inside the playground session

## EKS-Specific Issues

### "I ran 02-eks-up.sh but can't access the app in my browser"

**Most likely cause:** You only ran `02-eks-up.sh`, not `03-k8s-deploy.sh`.

`02-eks-up.sh` creates infrastructure (cluster, nodes, VPC) but does NOT deploy any application pods or LoadBalancer. You **must** run both scripts:

```bash
./scripts/advanced/02-eks-up.sh      # Creates cluster
./scripts/advanced/03-k8s-deploy.sh  # Deploys app
```

**Verify:**
```bash
kubectl get pods
# Empty = you skipped 03-k8s-deploy.sh
```

---

### "03-k8s-deploy.sh finished but the URL doesn't work"

**This is normal.** The script prints a URL when the LoadBalancer hostname is assigned, but the AWS Network Load Balancer needs an **additional 1–2 minutes** to fully provision before it serves traffic.

**What happens after `03-k8s-deploy.sh` finishes:**
1. LoadBalancer hostname is assigned ✓
2. AWS creates the NLB (~2–3 min)
3. NLB registers targets and runs health checks (~1–2 min)
4. DNS propagates (~2–5 min)

**What to do:**
```bash
# The script already polls for you, but if you closed the terminal:
LB_URL=$(kubectl get svc thermos-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -I http://${LB_URL}/
# Keep trying every 30 seconds for up to 5 minutes
```

---

### "EXTERNAL-IP stays <pending> forever"

**Cause 1:** Subnet tags are missing or incorrect.

The subnets MUST have these exact tags:
```
kubernetes.io/role/elb = 1
kubernetes.io/cluster/thermos-eks = shared
```

**Verify:**
```bash
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/cluster/thermos-eks,Values=shared" \
  --query 'Subnets[*].{ID:SubnetId,Tags:Tags}'
```

**Cause 2:** Classic Load Balancer is being created instead of NLB.

Check the Service annotation in `kubernetes/03-frontend.yaml`:
```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

**Cause 3:** KodeKloud IAM deny on ELB creation.

The playground blocks Classic Load Balancers but allows NLBs. If you see errors about `elasticloadbalancing:CreateLoadBalancer` being denied, the NLB annotation is missing.

---

### "Pods are stuck in Pending"

**Cause 1:** No worker node is Ready.

```bash
kubectl get nodes
# Should show at least one node with STATUS = Ready
```

If nodes show `NotReady`:
```bash
kubectl describe node <node-name>
# Check Events: at the bottom
```

**Cause 2:** Resource limits exceeded.

KodeKloud caps EKS at:
- 3 pods per namespace
- 256m CPU per pod
- 512Mi memory per pod

```bash
kubectl get events --sort-by=.lastTimestamp | grep FailedScheduling
```

If you see `Insufficient cpu` or `Insufficient memory`, check your pod resource requests/limits.

**Cause 3:** Pod limit exceeded.

If you already have 3 pods and try to add a 4th:
```bash
kubectl get pods --all-namespaces | grep thermos
# Count must be ≤ 3 in the default namespace
```

---

### "ImagePullBackOff on backend or frontend pod"

**Cause:** The ECR image doesn't exist or kubectl can't authenticate to ECR.

**Fix:**
```bash
# Re-run 03-k8s-deploy.sh to rebuild and push images
./scripts/advanced/03-k8s-deploy.sh

# Or manually:
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
docker build -t thermos-backend:latest -f src/backend/Dockerfile src/backend
docker tag thermos-backend:latest <ecr-repo>/thermos-backend:latest
docker push <ecr-repo>/thermos-backend:latest
```

---

### "NLB targets show as unhealthy"

**Cause 1:** Pods aren't ready yet.

```bash
kubectl get pods
# Wait until all show READY = 1/1
```

**Cause 2:** Readiness probe is failing.

```bash
kubectl describe pod <frontend-pod-name>
# Check Events: and Conditions:
```

**Cause 3:** Security group blocks NodePort range.

The NLB forwards traffic to a NodePort (30000–32767). The security group must allow this:

```bash
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(aws eks describe-cluster --name thermos-eks --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)"
```

Look for an ingress rule allowing TCP 30000–32767 from 0.0.0.0/0.

---

### "Node never joins the cluster"

**Check the node's console output:**
```bash
# Get the instance ID from the ASG
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names thermos-eks-node \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

# Get console logs
aws ec2 get-console-output --instance-id $INSTANCE_ID --output text | tail -50
```

**Common causes:**
- IAM instance profile doesn't have `AmazonEKSNodeRole` permissions
- `nodeadm` bootstrap failed (check for YAML syntax errors in user data)
- EKS cluster endpoint is not accessible from the node (security group blocks 443)

---

### "EKS cluster creation fails with IAM error"

**Cause:** The required IAM roles don't exist.

`02-eks-up.sh` creates them automatically, but if you ran `terraform apply` directly:

```bash
# Check if roles exist
aws iam get-role --role-name eksClusterRole
aws iam get-role --role-name AmazonEKSNodeRole

# If not found, run 02-eks-up.sh which creates them:
./scripts/advanced/02-eks-up.sh
```
