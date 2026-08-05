# terraform-docker

Deploys Thermos as Docker Compose on a single AWS EC2 instance.

## Files

| File | Purpose |
|------|---------|
| `providers.tf` | Terraform version constraints, AWS provider |
| `variables.tf` | Input variables (instance type, region, project name) |
| `main.tf` | Core resources: VPC, subnet, security group, EC2 instance |
| `outputs.tf` | Output values: EC2 IP, app URL, SSH command |
| `backend.tf` | Remote state backend template (S3 + DynamoDB) |
| `user_data.sh` | EC2 bootstrap script: installs Docker, builds app |

## Usage

```bash
cd terraform-docker
terraform init
terraform plan
terraform apply
```
