# =============================================================================
# outputs.tf — Output Values
# =============================================================================

output "cluster_name" {
  value = aws_eks_cluster.thermos.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.thermos.endpoint
}

output "ecr_backend_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "configure_kubectl_command" {
  description = "Run this to point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.thermos.name} --region ${var.aws_region}"
}

output "node_autoscaling_group" {
  description = "Self-managed worker node ASG (KodeKloud blocks managed node groups - see docs/03-kodekloud-aws-playground-limits.md)"
  value       = aws_autoscaling_group.node.name
}
