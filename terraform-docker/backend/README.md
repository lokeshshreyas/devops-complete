# terraform-docker/backend

Small, standalone Terraform config that bootstraps the remote state backend
(S3 bucket + DynamoDB lock table) shared by `terraform-docker/` and
`terraform-eks/`.

**You do not run Terraform here by hand.** It's applied for you by
[`../../scripts/advanced/01-setup-backend.sh`](../../scripts/advanced/01-setup-backend.sh)
and torn down by
[`../../scripts/advanced/05-destroy-backend.sh`](../../scripts/advanced/05-destroy-backend.sh).

See [`docs/09-remote-terraform-state.md`](../../docs/09-remote-terraform-state.md)
for the full explanation, including why this module intentionally keeps its
own state **local** (a bootstrap config can't safely store its state inside
the bucket it creates).

## Files

| File | Purpose |
|---|---|
| `providers.tf` | Terraform/AWS provider config — local state, on purpose |
| `variables.tf` | `aws_region`, `project_name` |
| `main.tf` | The S3 bucket (versioned, encrypted, `force_destroy = true`) + DynamoDB table (`PAY_PER_REQUEST`) |
| `outputs.tf` | `bucket_name`, `dynamodb_table_name`, `region` — read by `01-setup-backend.sh` |

## Manual usage (advanced / debugging only)

```bash
cd terraform-docker/backend
terraform init
terraform apply
terraform output
```
