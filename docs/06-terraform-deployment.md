# 6. Terraform Deployment

All AWS infrastructure lives in **one file**: `terraform-docker/main.tf`, plus the EC2 boot
script `terraform-docker/user_data.sh`. Both are unchanged from the original project — this
page just documents what they do and how to run them.

## What gets created

See [02-architecture.md](02-architecture.md) for the full resource table. In short: one VPC,
one public subnet, one internet gateway + route table, one security group, and one EC2
instance (default `t3.medium`) running Ubuntu 22.04.

## Choosing an instance type

`./scripts/03-deploy.sh` asks which EC2 instance type to use before running Terraform. Press
Enter to accept the default (`t3.medium`, recommended), or type another allowed type:
`t2.nano`, `t2.micro`, `t2.small`, `t2.medium`, `t3.nano`, `t3.micro`, `t3.small`. Smaller
types build/run more slowly and may run out of memory during `docker compose build` (see
[07-troubleshooting.md](07-troubleshooting.md)).

To skip the prompt, pass it directly: `./scripts/03-deploy.sh --instance-type=t3.small`.
`./scripts/03-deploy.sh -y` skips the prompt too and uses the default.

Whatever you choose is validated against `terraform-docker/variables.tf`'s `validation` block
(the same KodeKloud-allowed list) before Terraform ever runs.

## Deploy
