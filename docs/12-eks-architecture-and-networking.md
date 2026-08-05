# 12. EKS Architecture: Provisioning, Internal Design, and Client Traffic Flow

This document explains **how `terraform-eks/` provisions the cluster, how the pieces fit
together internally, how it connects to other AWS services, and exactly how an internet
client's HTTP request reaches the running application.** It's a companion to
[11-kubernetes-eks-optional.md](11-kubernetes-eks-optional.md) (the how-to-deploy guide) and
[03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md) (why some
design choices exist).

**Short answer up front: yes, this is designed to serve real internet client requests**, via
a public-facing AWS Network Load Balancer. Two real bugs were found and fixed to make that
actually true: the Service was defaulting to a **Classic** Load Balancer, which KodeKloud's
AWS Playground has a confirmed deny on (section 4.3) — this is the one that explains
"Terraform succeeded but nothing is reachable even after 20+ minutes." A second, smaller
subnet-tagging bug (section 4.4) was fixed alongside it.

---

## 1. How it's provisioned

`./scripts/advanced/02-eks-up.sh` runs two phases before your application ever touches the cluster:

```
02-eks-up.sh
 ├─ 1. IAM bootstrap (aws iam get-role / create-role, via AWS CLI - not Terraform)
 │     Creates "eksClusterRole" and "AmazonEKSNodeRole" if they don't already exist,
 │     with the exact managed policies EKS requires attached. KodeKloud's IAM
 │     restrictions are scoped around these two exact role names (see doc 03),
 │     so Terraform looks them up via `data "aws_iam_role"` rather than creating
 │     its own - custom role names would likely be denied.
 │
 └─ 2. terraform apply (terraform-eks/main.tf)
       Creates every AWS resource described in section 2 below, in dependency order:
       VPC → subnets → IGW → route table → EKS cluster → (IAM instance profile,
       launch template, ASG, access entry, ECR repos) in parallel once the cluster exists.
```

Cluster creation alone takes ~10-15 minutes (the EKS control plane's own provisioning
time, not something Terraform can speed up). Everything else (VPC, subnets, node ASG, ECR)
takes seconds to low minutes.

Once `terraform apply` finishes, `./scripts/advanced/03-k8s-deploy.sh` takes over: builds the
frontend/backend Docker images, pushes them to the two ECR repos Terraform just created,
points `kubectl` at the new cluster, and applies the four manifests in `kubernetes/`.

---

## 2. Internal design — what actually exists
