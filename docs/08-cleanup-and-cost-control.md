# 8. Cleanup and Cost Control

## Why this matters even on a "free" playground

KodeKloud AWS Playground sessions are time-boxed (commonly around 3 hours). Two things can
go wrong if you don't clean up:

1. **The session ends before you destroy resources.** The sandboxed AWS account is reclaimed
   along with everything in it, but during the session your `t3.medium` and its EBS volume
   are consuming real AWS capacity the whole time it exists — so destroy promptly out of
   courtesy to the shared resource pool, not just for your own benefit.
2. **You leave a stopped-but-not-terminated instance.** The playground's EC2 shutdown
   behavior is set to **Terminate**, and it enforces a max of 3 stopped instances before
   force-terminating everything — so "just stopping" the instance isn't a safe substitute
   for actually destroying it with Terraform.

## Recommended: `scripts/07-destroy.sh`

```bash
./scripts/07-destroy.sh
# type 'yes' to confirm
```

This does two things in one step:

1. Runs `terraform destroy` against `terraform-docker/`, removing the VPC, subnet, security
   group, and EC2 instance.
2. Runs a local Docker cleanup (`docker compose down`, prunes dangling images/volumes left
   over from `02-validate.sh` runs), so your machine doesn't accumulate leftover images every
   time you iterate.

Flags: `--aws-only` skips the local Docker cleanup; `--local-only` skips the AWS teardown.

## Verify everything is actually gone

```bash
./scripts/05-status.sh
# or directly:
aws ec2 describe-instances --filters "Name=tag:Project,Values=thermos" \
  --query 'Reservations[].Instances[].State.Name'
```

If this returns anything other than `terminated` (or an empty list), something didn't clean
up — re-run `terraform destroy` from `terraform-docker/` manually and check the error output.

## Estimated cost per full run

A `t3.medium` instance running Docker Compose for a full 3-hour KodeKloud session, plus its
EBS volume and negligible data transfer, costs on the order of a few cents. The real
"cost" of forgetting to clean up isn't the dollar amount — it's leaving resources running
against the shared, resource-limited playground account (see
[03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md)) for other
learners.

## Checklist before you close your KodeKloud session

- [ ] `./scripts/07-destroy.sh` (or `destroy-infrastructure.sh`) completed without errors
- [ ] `./scripts/05-status.sh` shows no running AWS resources for this project
- [ ] Any local Docker containers from `validate-local.sh` are stopped
  (`docker compose down` from the project root, if you skipped `cleanup.sh`)
