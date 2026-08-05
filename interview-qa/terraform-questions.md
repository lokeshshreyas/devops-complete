# Terraform — Interview Q&A (based on this project)

**Q: Why does `terraform-docker/main.tf` create a custom VPC instead of using the account's
default VPC?**
A: A default VPC works for quick experiments, but explicitly defining the VPC, subnet,
internet gateway, and route table makes every networking decision visible and reviewable —
which matters for learning. It also avoids depending on the KodeKloud account already having
a default VPC in the exact shape you expect (region-specific CIDR, etc.).

**Q: What does `metadata_options { http_tokens = "required" }` do on the `aws_instance`
resource, and why does it matter?**
A: It forces the instance to use IMDSv2 (token-based instance metadata requests) instead of
the older, insecure IMDSv1. IMDSv1 is a common SSRF-to-credential-theft vector; requiring
tokens closes that off. This is a security best practice even for a workshop project.

**Q: Why is `user_data` passed as `base64encode(file(...))` instead of inline HCL?**
A: Keeping the boot logic in a separate `user_data.sh` shell script makes it independently
readable, testable, and reusable outside Terraform, and keeps `main.tf` focused on resource
definitions rather than imperative bash. `base64encode` is simply the encoding EC2's
`user_data` field expects.

**Q: What would happen if you ran `terraform apply` twice in a row without changing
anything?**
A: Nothing new would be created — Terraform compares the desired state (your `.tf` files)
against the current state file and only changes what's different. This idempotency is why
the RUNBOOK says "just redeploy" as a fix for a broken environment: destroy, then apply
again from a clean slate.

**Q: Where is Terraform state stored in this project, and what's the tradeoff?**
A: Locally, as a `terraform.tfstate` file inside `terraform-docker/`. That's simple and
requires no extra AWS resources (no S3 bucket, no DynamoDB lock table), which fits a
single-user, short-lived workshop. The tradeoff: no locking (two people running `apply`
at once could conflict) and no state backup if the local file is lost — acceptable for this
scope, not for a team production environment.

**Q: Why `data "aws_ami" "ubuntu"` instead of a hardcoded AMI ID?**
A: AMI IDs are region-specific and get replaced over time as new patched images are
published. A data source that filters on name pattern and owner (`099720109477` = Canonical)
always resolves to the current latest matching AMI at apply-time, so the configuration
doesn't go stale or break when you switch AWS regions.

**Q: What's the purpose of the `local-exec` provisioner at the end of the `aws_instance`
resource?**
A: It just prints a friendly message ("EC2 instance is launching...") to the terminal
running `terraform apply` — it has no effect on the infrastructure itself. `local-exec`
provisioners are generally discouraged for anything that affects real infrastructure state,
since Terraform can't track or roll back their side effects; using one purely for a log
message is a safe, low-risk use of it.

**Q: Why does `main.tf` generate its own SSH key pair with `tls_private_key` instead of
asking you to create one manually in the AWS Console first?**
A: It removes an entire manual, error-prone step: creating a key pair in the console,
downloading the `.pem` file, remembering where you saved it, and getting the file
permissions right (`chmod 600`). With `tls_private_key` + `aws_key_pair` + `local_file`,
`terraform apply` produces a working, ready-to-use key automatically, and `terraform destroy`
cleans it up automatically too — no orphaned keys left in your AWS account or on disk.

**Q: Why does this project upload application code with Terraform's `file` provisioner
instead of having the EC2 instance `git clone` it from GitHub?**
A: `git clone` requires the code to already be pushed somewhere reachable (a public repo, or
one the instance can authenticate against) — an extra manual step and an extra point of
failure for something that's really just "get my local files onto that box." A `file`
provisioner uploads exactly what's on your machine at `terraform apply` time, over the same
SSH connection Terraform already needs for the key pair to be useful. The tradeoff:
HashiCorp's own docs call provisioners "a last resort" because Terraform can't track what a
provisioner does the way it tracks a resource — for anything beyond a workshop-scale, one-
instance deploy, you'd reach for something more track-able instead, like baking the app into
an AMI, pulling from S3/ECR, or a real CI/CD pipeline (as the companion
`ecommerce-devops-project` does with GitHub Actions).

**Q: How would you extend this to support multiple environments (dev/staging/prod)?**
A: Introduce Terraform workspaces or separate `.tfvars` files per environment, parameterize
things like `instance_type` and `cidr_block` as variables instead of hardcoded values, and
move state to a remote backend (S3 + DynamoDB lock table) so multiple people/environments
don't collide. That's exactly the direction the companion `ecommerce-devops-project`'s
`terraform/backend/` module takes.
