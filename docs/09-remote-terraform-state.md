# 9. Remote Terraform State (Optional)

**This is optional.** The core workshop in [RUNBOOK.md](../RUNBOOK.md) works perfectly with
local state — nothing here is required to deploy Thermos. Use this if you specifically want
hands-on practice with the "remote state + locking" pattern used on real teams.

## Why remote state at all?

Local state (a `terraform.tfstate` file sitting in `terraform-docker/`) works fine for one
person, one laptop, one deployment. It breaks down as soon as:

- Two people (or two CI jobs) run `terraform apply` at the same time — without locking, they
  can corrupt each other's state.
- Your laptop dies or you lose the file — there's no backup of what AWS resources actually
  exist.
- You want a teammate to run `terraform plan` and see the same state you do.

Remote state (state stored in S3) plus a DynamoDB lock table solves all three.

## Set it up

```bash
chmod +x scripts/advanced/01-setup-backend.sh
./scripts/advanced/01-setup-backend.sh
```

This:
1. Runs `terraform apply` inside `terraform-docker/backend/` — a small, separate Terraform
   config that creates exactly two things: an S3 bucket (versioned, encrypted, private) and
   a DynamoDB table (for locking, pay-per-request billing so it's free when idle).
2. Writes **both** `terraform-docker/backend.tf` **and** `terraform-eks/backend.tf`, pointing
   at that *same* bucket/table but with a different state `key` each, so the two modules'
   state files never collide:
   - `terraform-docker/terraform.tfstate`
   - `terraform-eks/terraform.tfstate`
3. Re-runs `terraform init` in whichever of those two modules already has local state
   (`-migrate-state`, copying it into S3). A module you haven't applied yet is simply
   initialized fresh against the new backend — there's nothing local to migrate.

From this point on, **every script that runs Terraform needs no changes at all**
(`./scripts/03-deploy.sh`, `./scripts/07-destroy.sh`, `./scripts/advanced/02-eks-up.sh`,
`./scripts/advanced/04-k8s-destroy.sh`) — Terraform automatically picks up each module's
`backend.tf` and uses S3 for state.

## Verify it worked

```bash
cat terraform-docker/backend.tf     # shows the bucket/table Terraform is now using
cat terraform-eks/backend.tf        # same bucket/table, different state key
aws s3 ls s3://<bucket-name>/       # should show terraform-docker/ and/or terraform-eks/ folders
```

## Tear it down

Order matters — the state file(s) for your infrastructure live inside this S3 bucket,
so destroy the infrastructure *using* it first:

```bash
./scripts/07-destroy.sh                   # 1. destroy the EC2/VPC infrastructure (as always)
./scripts/advanced/04-k8s-destroy.sh      # 2. if you ever ran 02-eks-up.sh, destroy that too
./scripts/advanced/05-destroy-backend.sh  # 3. THEN destroy the S3 bucket + DynamoDB table
```

`05-destroy-backend.sh` asks you to confirm you've already run cleanup first, since destroying
the bucket before the state files inside it are empty would strand that state.

## Going back to local state

Delete `terraform-docker/backend.tf` (and/or `terraform-eks/backend.tf`) and run
`terraform init` again in that module — Terraform will offer to migrate state back to local.
(Simplest: run `./scripts/advanced/05-destroy-backend.sh`, which does this for both modules
automatically as its last step, restoring each `backend.tf` to its original inactive template
from the matching `backend.tf.template` file.)

## What this teaches

- The `backend "s3" { ... }` block in a `terraform` configuration block
- Why backend blocks can't reference variables (they're evaluated before any variables are
  loaded) — which is why `01-setup-backend.sh` *generates* `backend.tf` with literal values
  instead of trying to parameterize it
- State locking via DynamoDB, and what happens if you try to `terraform apply` twice at once
  (`Error: Error acquiring the state lock`)
- Why `force_destroy = true` and `PAY_PER_REQUEST` billing matter for a short-lived learning
  account specifically (see `terraform-docker/backend/main.tf`'s comments)
