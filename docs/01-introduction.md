# 1. Introduction

## What is Thermos?

Thermos is a small 3-tier web application (React frontend, Flask backend API, PostgreSQL
database) used to teach core DevOps fundamentals: containerization with Docker, local
orchestration with Docker Compose, and cloud deployment with Terraform on AWS.

It is deliberately **simplified** compared to production-grade projects (like the companion
`ecommerce-devops-project`): one EC2 instance instead of a Kubernetes cluster, one Terraform
file instead of a multi-module setup, and Docker Compose instead of Kubernetes manifests.

## Who is this for?

- DevOps freshers doing their first end-to-end cloud deployment
- Anyone with a time-boxed KodeKloud AWS Playground session (3 hours)
- Learners who want to understand *every* piece of infrastructure they create, without
  abstractions hiding what's happening underneath

## What you'll practice

- Building and running multi-container applications with Docker Compose
- Writing and applying a single, well-commented Terraform configuration
- Provisioning a VPC, subnet, internet gateway, security group, and EC2 instance
- Using an EC2 `user_data` script to bootstrap an application automatically on boot
- Verifying a deployment end-to-end, then tearing it down cleanly

## Instead of... / Best for...

| Complex (production pattern) | Simplified (this project) |
|---|---|
| 20+ Terraform files | 1 `main.tf` |
| Multi-AZ EKS cluster | Single `t3.medium` EC2 instance |
| NAT gateways + private subnets | Single public subnet |
| Kubernetes manifests | Docker Compose |
| ArgoCD GitOps | Manual `terraform apply` |
| ECR image registry | Local Docker builds |
| Remote state (S3 + DynamoDB locking) | Local Terraform state |

This project is best for:

- ✅ Learning DevOps fundamentals without unnecessary complexity
- ✅ Understanding each infrastructure component in isolation (EC2, VPC, security groups, Docker)
- ✅ A quick, time-boxed workshop that deploys and verifies an app end-to-end
- ✅ Staying safely inside KodeKloud AWS Playground limits (see
  [03-kodekloud-aws-playground-limits.md](03-kodekloud-aws-playground-limits.md))

## Where to go next

Start with **[RUNBOOK.md](../RUNBOOK.md)** in the project root for the actual step-by-step
deployment. Come back to this `docs/` folder for reference material as you go.
