# Changelog

> Newest first. Each entry explains what changed and why, so you can see the
> reasoning behind the project's current state, not just a diff.

## v14 — Backend Bootstrap Fix, Numbered Advanced Scripts, Opt-In CD

### Bug fix: missing remote-state bootstrap module

- **`terraform-docker/backend/` did not exist**, even though `scripts/advanced/setup-backend.sh`,
  `scripts/advanced/destroy-backend.sh`, `.github/workflows/ci.yml`, and
  `docs/09-remote-terraform-state.md` all referenced it. Running the setup script failed with
  `cd: .../terraform-docker/backend: No such file or directory`. Added the module
  (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, `README.md`) — an S3 bucket
  (versioned, encrypted, `force_destroy = true`) + a DynamoDB lock table, deliberately using
  local state (a bootstrap config can't store its own state inside the bucket it creates).
- **`setup-backend.sh` only wired up `terraform-docker/backend.tf`**, silently skipping
  `terraform-eks/backend.tf` — contradicting this very changelog's earlier claim (v13) of a
  "unified backend configuration for both modules." Fixed to configure both from one shared
  bucket/table, with separate state keys (`terraform-docker/terraform.tfstate` and
  `terraform-eks/terraform.tfstate`).
- **`destroy-backend.sh` had the same one-module gap**, and simply deleted `backend.tf` instead
  of restoring it to its documented "inactive template" state. Added `backend.tf.template`
  (a pristine, checked-in copy) to both modules; destroy now restores from it.

### Cleanup: numbered advanced scripts

- **`scripts/advanced/*.sh` had no numeric prefixes**, unlike `scripts/*.sh` (`01`–`07`),
  making the intended run order unclear. Renamed in logical order:
  `01-setup-backend.sh`, `02-eks-up.sh`, `03-k8s-deploy.sh`, `04-k8s-destroy.sh`,
  `05-destroy-backend.sh` — and updated every reference across the README, RUNBOOK, this
  changelog, `docs/`, `terraform-eks/README.md`, and the CI workflow.

### New: opt-in CD (Continuous Deployment)

- Added **`scripts/advanced/06-setup-cicd.sh`** — pushes this project to a GitHub repository
  you provide and registers your current AWS session credentials as GitHub Actions secrets.
  Explains, in its header comment, exactly which GitHub PAT type and permissions are needed.
- Added **`.github/workflows/cd.yml`** — on every push to `main` touching Terraform,
  Kubernetes, or app source, runs `scripts/advanced/07-cd-apply.sh`.
- Added **`scripts/advanced/07-cd-apply.sh`** — a non-interactive apply script (usable by CI
  or by hand) that reads a new **`.thermos/active-stack`** marker (written by `03-deploy.sh`
  and `03-k8s-deploy.sh`) to know whether to apply against the Docker/EC2 stack or the
  Kubernetes/EKS stack, and fails fast with an actionable message if the stored AWS
  credentials have expired — the expected outcome once a KodeKloud session ends.
- Added **`docs/16-cicd-continuous-deployment.md`**, documenting the full design, the
  KodeKloud session-credential limitation and required refresh workflow, and how this would
  differ (OIDC federation, no static keys) on a permanent AWS account.
- Updated `docs/10-cicd-pipeline.md` to point to the new doc; CI itself (`ci.yml`) is
  unchanged — it still runs credential-free on every push, by design.

No logical or functional changes were made to Level 1 (the required workshop) or to the
application code — this release only fixes the reported bug, improves discoverability of
`scripts/advanced/`, and adds the new opt-in CD capability.

---

## v13 — Industry-Standard Terraform Structure + terraform-docker Rename

### Major Restructure

- **Renamed `terraform-simple/` → `terraform-docker/`**. The old name confused freshers
  who thought it was "simpler Terraform" rather than "Terraform that deploys Docker Compose
  on EC2". The new name clearly indicates what the module does.
- **Split monolithic `main.tf` into industry-standard files** for BOTH modules:
  - `providers.tf` — Terraform version constraints and provider configuration
  - `variables.tf` — All input variables in one place
  - `main.tf` — Core resources only
  - `outputs.tf` — All output values in one place
  - `backend.tf` — Remote state backend template (S3 + DynamoDB)
  - `user_data.sh` — EC2 bootstrap script (terraform-docker only)
  - `README.md` — Module-specific documentation
- **Unified backend configuration for both modules.** `01-setup-backend.sh` now generates
  `backend.tf` for BOTH `terraform-docker/` and `terraform-eks/` with separate state keys:
  - `terraform-docker/terraform.tfstate`
  - `terraform-eks/terraform.tfstate`
  Both use the same S3 bucket and DynamoDB lock table.

### Documentation

- **Added `docs/15-terraform-docker-vs-eks.md`** — Comprehensive comparison document
  covering architecture, feature comparison, directory structure, learning path,
  and FAQ. Helps freshers choose the right deployment path.

### Script Updates

- Updated ALL scripts to use `terraform-docker/` instead of `terraform-simple/`.
- Fixed `01-setup-backend.sh` to configure backends for both modules simultaneously.

---

## v11b — EKS Deployment Fixes: NLB Polling, Health Checks, Documentation

### EKS-Specific Fixes

- **`scripts/advanced/03-k8s-deploy.sh`: Added active NLB URL polling.** Previously the script
  exited immediately after getting the LoadBalancer hostname, telling the user to wait
  "another minute or two" for DNS. In reality, AWS Network Load Balancer provisioning
  takes 1–2 minutes after hostname assignment, and DNS propagation can take 2–5 more
  minutes. The script now polls the actual URL with `curl` for up to 10 minutes and
  only reports success when the endpoint truly responds.
- **`scripts/advanced/03-k8s-deploy.sh`: Added prominent pre-flight check.** The script now
  detects if `02-eks-up.sh` was never run (no `terraform.tfstate` in `terraform-eks/`) and
  prints a clear error explaining the two-step deployment requirement, instead of
  failing cryptically later.
- **`kubernetes/03-frontend.yaml`: Added NLB health check annotations.** Without these,
  AWS uses aggressive default health check settings that can mark targets as unhealthy
  before the frontend pod finishes its readiness probe, causing the LoadBalancer to
  return no traffic even though the pod is fine. Added:
  `aws-load-balancer-healthcheck-interval`, `timeout`, `unhealthy-threshold`,
  `healthy-threshold`.
- **`docs/11-kubernetes-eks-optional.md`: Added prominent timing warning at the top.**
  Many users expected EKS to be as fast as the EC2 deployment (1–2 minutes). The doc
  now clearly states the 20–30 minute total timeline and the mandatory two-script
  sequence (`02-eks-up.sh` → `03-k8s-deploy.sh`) right at the top.
- **`docs/13-checking-and-monitoring.md`: Added full EKS monitoring section (Section 8).**
  Covers checking cluster status, nodes, pods, LoadBalancer service, NLB target health,
  live logs, cluster events, and a detailed timing reference table.
- **`docs/14-complete-walkthrough.md`: Added Level 2 EKS walkthrough section.**
  Step-by-step EKS deployment instructions with expected output, verification commands,
  and teardown instructions.
- **`docs/07-troubleshooting.md`: Added comprehensive EKS troubleshooting section.**
  Covers: app not accessible after 02-eks-up.sh, URL not working after 03-k8s-deploy.sh,
  EXTERNAL-IP pending, Pending pods, ImagePullBackOff, unhealthy NLB targets,
  node join failures, and IAM role errors.

---

## v11 — Principal Architect Audit: Fixed Deployment Failures, Cleaned Scripts, Simplified for Freshers

### Critical Fixes

- **`terraform-docker/user_data.sh`: Added 2 GB swap space.** The `t3.medium` instance (4 GB RAM)
  was running out of memory during `docker compose build` — specifically the React frontend's
  `npm install` and `npm run build` steps. This caused the build to hang or get killed by the
  OOM killer, leaving the app unreachable. Swap prevents the crash and allows the build to
  complete (albeit slowly — this is expected on a 1GB instance).
- **`terraform-docker/user_data.sh`: Fixed IMDSv2 metadata retrieval.** `main.tf` correctly sets
  `http_tokens = "required"` for security, but `user_data.sh` was using plain `curl` to the
  instance metadata endpoint, which returns 401 under IMDSv2. Fixed by requesting a token first.
- **`docker-compose.yml`: Removed hardcoded `REACT_APP_API_URL`.** The frontend was being built
  with `http://localhost:5000/api`, which meant on AWS the browser tried to call the API on
  the user's own machine instead of the EC2 instance. The frontend now uses relative `/api`
  URLs, and Nginx proxies them correctly to the backend — works identically on localhost and AWS.
- **`scripts/04-verify.sh` (was verify-deployment.sh): Increased timeout to 10 minutes.** On a
  `t3.medium`, Docker Compose build + startup can take 5–8 minutes. The old 200-second timeout
  was too aggressive and always failed. New default: 40 attempts × 15 seconds = 600 seconds.
- **`scripts/05-status.sh` (was status.sh): Now queries AWS EC2 directly.** Previously it only
  read `terraform.tfstate`, so it reported "nothing deployed" when remote state was used or the
  local file was missing. It now calls `aws ec2 describe-instances` with the Project=thermos
  filter to show real instance status regardless of where state is stored.
- **`scripts/06-ssh.sh` (was ssh-connect.sh): Dramatically improved key discovery.** Now clearly
  prints the exact key path from Terraform output, warns if the file is missing, and shows the
  exact manual SSH command to copy-paste. Prevents the "Permission denied (publickey)" error
  caused by running `ssh` from the wrong directory.

### Script Cleanup & Simplification

- **Removed duplicate/overlapping scripts.** `deploy.sh` and `deploy-all.sh` were merged into a
  single `03-deploy.sh` with clear flags. `destroy-infrastructure.sh` and `cleanup.sh` were
  merged into `07-destroy.sh`. Freshers no longer need to guess which script to run.
- **All Level 1 scripts are now numbered (01–07)** in exact run order. No more guessing the
  sequence.
- **Level 2 (optional) scripts moved to `scripts/advanced/`**. Freshers doing the core workshop
  are no longer overwhelmed by EKS/Kubernetes files they don't need.
- **Every script has a clear, consistent header** explaining exactly what it does, how long it
  takes, and what prerequisites it needs.

### Minor Fixes

- **`src/backend/Dockerfile` (production): Added `curl` installation.** The Docker Compose
  healthcheck uses `curl`, but the production Dockerfile didn't install it. While the current
  `docker-compose.yml` uses `Dockerfile.dev` (which has curl), this ensures consistency if
  the compose file is ever changed.
- **`terraform-docker/main.tf`: Outputs now print the absolute key path in a bright, unmissable
  block.** Freshers were missing the key location because it was buried in other output.
- **All doc cross-references updated** to point at the new numbered script names.

---

## v10 — Fixed EKS `postgres` Pod Stuck `Pending` with "Too many pods"

A user reported `scripts/advanced/03-k8s-deploy.sh` timing out at Step 5/5 with the `postgres`
Deployment never becoming ready, `kubectl describe pod` showing
`0/1 nodes are available: 1 Too many pods`, and a `FailedScheduling` event on the pod — even
though the cluster only defines 3 pods total, well under the playground's 3-pods-per-namespace
cap.

**Root cause and fix:** see the `node_instance_type` comment block in `terraform-eks/variables.tf`
for the full explanation — in short, `t3.micro`'s VPC CNI pod-slot allowance (~4 slots) is fully
consumed by system daemonsets before any app pod is scheduled, while `t3.medium` (~17 slots)
comfortably fits everything. `t3.medium` became the project default as a result of this issue.

---
