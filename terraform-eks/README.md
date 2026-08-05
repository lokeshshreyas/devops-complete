# terraform-eks

Deploys Thermos on AWS EKS (Elastic Kubernetes Service) with self-managed worker nodes
(a Launch Template + Auto Scaling Group, not an `aws_eks_node_group`) - see the "Worker
nodes" comment block in `main.tf` for why: the KodeKloud AWS Playground has an explicit
IAM deny on `eks:CreateNodegroup`.

## Files

| File | Purpose |
|------|---------|
| `providers.tf` | Terraform version constraints, AWS provider |
| `variables.tf` | Input variables (cluster name, region, instance type) |
| `main.tf` | Core resources: VPC, EKS cluster, ASG, ECR repos, NLB |
| `outputs.tf` | Output values: cluster name, ECR URLs, kubectl config command |
| `backend.tf` | Remote state backend - inactive template until `../scripts/advanced/01-setup-backend.sh` runs |
| `backend.tf.template` | Pristine copy of the inactive template, restored by `../scripts/advanced/05-destroy-backend.sh` |

## Usage

```bash
cd terraform-eks
terraform init
terraform plan
terraform apply
```

Then deploy the application:
```bash
../scripts/advanced/03-k8s-deploy.sh
```
