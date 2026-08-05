# =============================================================================
# variables.tf — Input Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region. KodeKloud AWS Playground supports us-east-1, us-west-2, us-east-2."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to tag and name every resource."
  type        = string
  default     = "thermos"
}

variable "node_instance_type" {
  # NOTE ON THE DEFAULT: t3.micro is technically allowed by the playground,
  # but its VPC CNI ENI/IP allocation only yields ~4 schedulable pod slots
  # per node (max-eni * (ips-per-eni - 1) + 2). The aws-node and kube-proxy
  # daemonsets plus CoreDNS already consume all 4 of those slots on a fresh
  # node, leaving zero room for postgres/backend/frontend - they get stuck
  # "Pending" forever with a "Too many pods" FailedScheduling event, even
  # though the cluster is nowhere near the playground's 2000m CPU / 4096Mi
  # memory or 3-pods-per-namespace caps. t3.medium's larger ENI/IP allowance
  # (~17 pod slots) comfortably fits system pods + all 3 app pods on a
  # single node, so it's the default here even though t3.micro remains a
  # selectable option for anyone who's already worked around the pod-slot
  # limit (e.g. via VPC CNI prefix delegation).
  description = "EKS worker node instance type. Restricted to t3.micro or t3.medium. t3.medium is the default because t3.micro's pod-slot limit (~4) is fully consumed by system daemonsets before any app pod is scheduled - see comment above."
  type        = string
  default     = "t3.medium"

  validation {
    condition     = contains(["t3.micro", "t3.medium"], var.node_instance_type)
    error_message = "node_instance_type must be one of: t3.micro, t3.medium."
  }
}

variable "desired_node_count" {
  description = "Desired number of worker nodes. KodeKloud limits node groups to 3 nodes max. Default of 1 is enough since kubernetes/ only runs 3 pods total (see docs/11-kubernetes-eks-optional.md's namespace pod cap)."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_node_count >= 1 && var.desired_node_count <= 3
    error_message = "desired_node_count must be between 1 and 3 (KodeKloud AWS Playground EKS node group limit)."
  }
}
