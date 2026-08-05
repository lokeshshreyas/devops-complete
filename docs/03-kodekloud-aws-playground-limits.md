# 3. KodeKloud AWS Playground — Limits This Project Respects

Source: [kodekloud.com/cloud-playgrounds/aws](https://kodekloud.com/cloud-playgrounds/aws)
(check that page directly before you deploy — limits can change, and this document is a
snapshot for guidance, not a guarantee). Last checked: July 2026.

## Supported regions

| Region code | Region name |
|---|---|
| `us-east-1` | US East (N. Virginia) |
| `us-west-2` | US West (Oregon) |
| `us-east-2` | US East (Ohio) |

`terraform-docker/main.tf` and `terraform-eks/main.tf` both default to `us-east-1`. If your
playground session uses a different supported region, change the `aws_region` variable in
whichever config you're using (and the subnet's `availability_zone` in
`terraform-docker/main.tf`).

## Level 1 (required workshop): EC2

| Playground limit | This project |
|---|---|
| Allowed instance types: `t2`/`t3` `.nano`/`.micro`/`.small`/`.medium` | `instance_type` variable defaults to `t3.medium`, with a `validation` block rejecting anything else ✅ |
| T-series must run in **Standard** CPU credit mode (Unlimited mode is blocked and can suspend your session) | Terraform doesn't set `credit_specification`, which defaults to Standard ✅ |
| Max 2 vCPUs / 4 GB RAM per instance | `t3.medium` = 2 vCPU, 4 GB RAM — well under the cap ✅ |
| Max 10 concurrent instances, **and total EC2 instances account-wide capped at 5** | This project's core workshop creates exactly 1 instance ✅ |
| EBS: GP2/GP3 only, max 30 GB per volume | `root_block_device` explicitly sets `volume_type = "gp3"`, `volume_size = 15` ✅ |
| No more than 3 **stopped** instances (violation terminates all of them) | Instance shutdown behavior is set to **Terminate**, so it never lingers in a stopped state — just make sure you run `destroy`, not `stop` |
| No Spot Instances, Dedicated Hosts, Capacity Reservations, Scheduled Instances, or Fast Snapshot Restores | Not used ✅ |
| No VPN connections/gateways/transit gateways/traffic mirroring | Not used — this project uses a plain Internet Gateway only ✅ |
| A default VPC must exist (create one if it doesn't) | Not required by this project — it creates its **own** VPC/subnet/IGW instead of relying on the default one ✅ |

**Account-wide EC2 cap matters if you also run Level 2.** The playground limits you to **5
total EC2 instances** across your whole account. The core workshop uses 1; the optional EKS
node group (Level 2, below) defaults to 1 more — 2 total if both run at once, comfortably
under the cap. Don't raise the EKS node count past 2 while the core workshop instance is
also running unless you've checked your current total.

## Level 2 (optional): EKS, S3, DynamoDB, ECR

This project's optional `terraform-eks/` + `kubernetes/` path was specifically checked
against the playground's EKS section, which is stricter than EC2's:

| Playground limit | This project |
|---|---|
| **Service Roles Permitted: Cluster role `eksClusterRole`, Node role `AmazonEKSNodeRole`** (these exact names) | `terraform-eks/main.tf` looks these roles up via `data "aws_iam_role"` rather than creating custom-named ones; `scripts/advanced/02-eks-up.sh` creates them first with these exact names if they don't already exist ✅ |
| Allowed EKS node instance types: `t2`/`t3` `.nano`/`.micro`/`.small`/`.medium` | `node_instance_type` variable defaults to `t3.medium`, restricted by this project to just `t3.micro` or `t3.medium` (a deliberately narrower subset of what the playground itself allows) ✅. **`t3.micro` is allowed by the playground but not used as the default** - its VPC CNI ENI/IP allocation only yields ~4 schedulable pod slots per node, all of which the `aws-node`/`kube-proxy` daemonsets and CoreDNS already consume, leaving no room to schedule `postgres`/`backend`/`frontend` (they hang `Pending` with a `Too many pods` `FailedScheduling` event - unrelated to the pod/CPU/memory caps below, which this project is nowhere near). `t3.medium` has a much larger ENI/IP allowance (~17 pod slots) and comfortably fits everything on a single node |
| Limit of 3 EC2 nodes per node group | `desired_node_count` defaults to 1, capped at `max_size = 3` in the scaling config, with a `validation` block enforcing the 1–3 range ✅ |
| Max CPU per pod: 256 millicores; max memory per pod: 512 MiB | Every container in `kubernetes/*.yaml` sets `limits.cpu: "200m"` and `limits.memory` well under 512Mi ✅ |
| Max 3 pods per namespace | `postgres`, `thermos-backend`, and `thermos-frontend` each run exactly 1 replica — 3 pods total in the default namespace ✅ |
| Cumulative cluster caps: 2000m CPU / 4096 MiB memory | 3 pods × 200m CPU / ≤256Mi memory each ≈ 600m CPU / ~640Mi total — well under ✅ |
| 3 Fargate profiles per cluster | Not used — this project uses a self-managed EC2 Auto Scaling Group, not Fargate |
| **Classic Load Balancers are denied; Application/Network Load Balancers are allowed** (confirmed by KodeKloud staff on their community forum — not documented on the limits page itself) | `kubernetes/03-frontend.yaml`'s Service carries the `service.beta.kubernetes.io/aws-load-balancer-type: "nlb"` annotation, so Kubernetes' built-in AWS controller provisions a Network Load Balancer instead of defaulting to a Classic one ✅ — see [docs/12-eks-architecture-and-networking.md §4.3](12-eks-architecture-and-networking.md#43-the-real-confirmed-blocker--classic-elb-is-denied-in-the-playground) for the full story |
| DynamoDB: `PAY_PER_REQUEST` billing mode | `terraform-docker/backend/main.tf`'s lock table uses `billing_mode = "PAY_PER_REQUEST"` ✅ |
| S3 bucket names must be unique (add randomness) | `terraform-docker/backend/main.tf` appends a `random_id` suffix to the bucket name ✅ |
| ECR: scanning enabled | Both ECR repos in `terraform-eks/main.tf` set `image_scanning_configuration { scan_on_push = true }` ✅ |

### ⚠️ EKS node groups are blocked in the playground

The playground's public limits page lists EKS as supported and names the two service roles
it permits, but it does **not** mention one important restriction found by testing: the
playground's IAM policy carries an **explicit `Deny` on `eks:CreateNodegroup`** for the lab
user, regardless of role name, instance type, or whether you use Terraform, the CLI, or the
Console. Attempting it fails with:

```
AccessDeniedException: User: arn:aws:iam::<account>:user/kk_labs_user_xxxxxx is not
authorized to perform: eks:CreateNodegroup on resource: ... because no identity-based
policy allows the eks:CreateNodegroup action
```

(Some accounts see this phrased as `... with an explicit deny` instead — same root cause.)

KodeKloud staff have confirmed this directly in their community forum ("You cannot create
managed node groups in playground.") — it's a hard platform restriction, not something a
different Terraform config or IAM role can work around.

**This project's fix:** `terraform-eks/main.tf` does **not** use `aws_eks_node_group`. Instead
it creates worker nodes the pre-managed-node-groups way: a Launch Template + Auto Scaling
Group of plain EC2 instances running the Amazon Linux 2023 EKS-optimized AMI (bootstrapped via
`nodeadm`'s YAML `NodeConfig`, not the older `bootstrap.sh`), registered with the cluster via
an EKS Access Entry (`type = "EC2_LINUX"`) instead of a node group or a hand-edited `aws-auth`
ConfigMap. None of those calls touch `eks:CreateNodegroup`, so they aren't affected by the
deny, and everything still runs on the same `AmazonEKSNodeRole` / `t2`/`t3` instance-type
constraints as before.

Two gotchas worth knowing if you ever touch this again:
- **AL2 vs AL2023 AMIs.** AWS stopped publishing Amazon Linux 2 EKS-optimized AMIs for newer
  Kubernetes versions — the SSM parameter path `.../amazon-linux-2/...` will 404 with
  `couldn't find resource` on a recent cluster version. `terraform-eks/main.tf` uses the
  `amazon-linux-2023` path and `nodeadm`-style `NodeConfig` user data instead.
- **`access_config.bootstrap_cluster_creator_admin_permissions` is a ForceNew field.** If you
  ever add or modify the `access_config` block on an *existing* cluster without setting this
  explicitly, Terraform computes it as unset/`null`, which differs from the real cluster's
  actual value and forces a full cluster replacement. Always set it explicitly (matching
  whatever the cluster already has — `true` for clusters created without an explicit
  `access_config`, which is AWS's default) so no diff is generated.

**If `eksClusterRole` or `AmazonEKSNodeRole` already exist from an earlier session** and
`scripts/advanced/02-eks-up.sh` reports `EntityAlreadyExists`, that's fine — the script checks for this
and reuses the existing role rather than failing. If it instead reports "no IAM Role found"
during `terraform apply`, re-run `./scripts/advanced/02-eks-up.sh` (not `terraform apply` directly) so the
role-creation step runs first.

See [docs/11-kubernetes-eks-optional.md](11-kubernetes-eks-optional.md) for the full Level 2
walkthrough.

## Session and cost mechanics

- KodeKloud playground sessions are time-boxed (commonly ~3 hours per session). Whatever you
  create must be destroyed before the session ends, or it's simply reclaimed along with the
  whole sandboxed AWS account.
- Estimated cost for a full 3-hour run of **Level 1 alone**: a few cents (`t3.medium` for a few
  hours + 15 GB of GP3 EBS + negligible data transfer).
- **Level 2 (EKS) costs meaningfully more** — the EKS control plane bills hourly regardless of
  cluster size, on top of the node group's EC2 instance(s) and the frontend's Load Balancer.
  Only bring it up when you're actively using it.
- **Always run `./scripts/07-destroy.sh`** (Level 1) **and/or `./scripts/advanced/04-k8s-destroy.sh`**
  (Level 2) **before your session ends.** See
  [08-cleanup-and-cost-control.md](08-cleanup-and-cost-control.md).

## Other limits worth knowing (not used by this project, but common gotchas)

- **Lambda:** memory capped at 256 MB, timeout at 10 seconds; timeouts over 30s trigger a
  policy violation and session suspension.
- **RDS:** `*.micro`/`*.small`/`*.medium` burstable instance classes only, single-AZ only, GP2/GP3
  storage, max 30 GB. (This project uses containerized PostgreSQL instead, so RDS limits
  don't apply — but worth knowing if you extend the project.)
- **CodeBuild/CodePipeline:** compute types limited to `BUILD_GENERAL1_SMALL` /
  `BUILD_LAMBDA_1GB` / `BUILD_LAMBDA_2GB`; max 5 CodeBuild projects and 3 CodePipeline
  pipelines per account. Not used by this project's CI (`.github/workflows/ci.yml` runs on
  GitHub's own runners, not AWS CodeBuild).

If you plan to extend this project further, re-check the current limits page first —
KodeKloud updates these periodically and violations can pause your whole session, not just
the one resource.

## Practical checklist before you `terraform apply`

**Level 1 (required):**
- [ ] Region is `us-east-1` (or another supported region, updated in `main.tf`)
- [ ] Instance type is `t3.medium` (already the default — don't bump it up "for speed")
- [ ] You're not requesting Spot, Unlimited CPU credits, or a second concurrent instance
- [ ] You have a plan to destroy the stack well before your session's time limit

**Level 2 (optional, if you use it):**
- [ ] You ran `./scripts/advanced/02-eks-up.sh` (not raw `terraform apply`) so the required IAM roles get
  created first
- [ ] Node instance type is `t3.medium` (already the default - `t3.micro` is also allowed by
  the `validation` block but leaves no schedulable pod slots free for the app once system
  daemonsets are accounted for, see the EKS table above), and node count is 1–3
- [ ] You know Level 2 costs more than Level 1 and plan to run `./scripts/advanced/04-k8s-destroy.sh`
  promptly when you're done experimenting
