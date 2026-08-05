# =============================================================================
# main.tf — Core Infrastructure Resources
# =============================================================================

# =============================================================================
# terraform-eks/main.tf
#
# OPTIONAL "Level 2" infrastructure: a small EKS cluster to run the Thermos
# Kubernetes manifests in kubernetes/. This is completely separate from
# terraform-docker/ (the core, required workshop) - you do NOT need this to
# complete the main RUNBOOK.md workshop.
#
# Kept deliberately small and within KodeKloud AWS Playground's EKS limits:
#   - node instance types: t2/t3 nano-medium only
#   - max 3 worker nodes
#   - uses KodeKloud's pre-provisioned "eksClusterRole" / "AmazonEKSNodeRole"
#     IAM roles (via data sources) instead of creating custom ones - the
#     Playground's IAM restrictions are built around these two exact roles
#   - worker nodes are SELF-MANAGED (Launch Template + Auto Scaling Group),
#     not an aws_eks_node_group, because the Playground has an explicit IAM
#     deny on eks:CreateNodegroup - see the "Worker nodes" section below
# See docs/03-kodekloud-aws-playground-limits.md and docs/11-kubernetes-eks-optional.md.
#
# IMPORTANT: EKS's control plane alone costs money for every hour it exists
# and is NOT covered by the free tier. Only run this if you intend to
# actively use it, and destroy it (scripts/advanced/04-k8s-destroy.sh) as soon as you're
# done - don't leave it running for the rest of your KodeKloud session.
# =============================================================================

# =============================================================================
# Networking - separate 10.1.0.0/16 range so this can coexist with
# terraform-docker's 10.0.0.0/16 VPC if both happen to be deployed at once.
# EKS requires subnets in at least 2 Availability Zones.
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "eks" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-eks-vpc"
  }
}

resource "aws_internet_gateway" "eks" {
  vpc_id = aws_vpc.eks.id
  tags   = { Name = "${var.project_name}-eks-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.1.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  # Required tags for EKS + ALB/ELB auto-discovery. The cluster-name tag MUST
  # match the EKS cluster's actual name exactly ("${var.project_name}-eks",
  # not just "${var.project_name}") - AWS's LoadBalancer provisioning uses
  # this tag to auto-discover which subnets it's allowed to place an ELB in.
  # A mismatch here means a `type: LoadBalancer` Service silently never gets
  # an EXTERNAL-IP - the client-facing path looks correct everywhere else,
  # but nothing external can ever reach it.
  tags = {
    Name                                             = "${var.project_name}-eks-public-${count.index}"
    "kubernetes.io/role/elb"                         = "1"
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks.id
  }
  tags = { Name = "${var.project_name}-eks-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# IAM - KodeKloud AWS Playground compatibility
#
# IMPORTANT: the KodeKloud AWS Playground only permits EKS to use its own
# pre-provisioned service roles - "eksClusterRole" and "AmazonEKSNodeRole"
# (see docs/03-kodekloud-aws-playground-limits.md). Creating brand-new,
# custom-named IAM roles for EKS is very likely to be denied on this
# sandboxed account. So instead of creating roles, we look up the ones
# KodeKloud already provisioned for you.
#
# If this lookup fails with "no IAM Role found", the roles haven't been
# provisioned in your account yet - see docs/11-kubernetes-eks-optional.md
# for how to trigger their creation first.
# =============================================================================

data "aws_iam_role" "cluster" {
  name = "eksClusterRole"
}

data "aws_iam_role" "node" {
  name = "AmazonEKSNodeRole"
}

# =============================================================================
# EKS Cluster
#
# The access_config block below sets authentication mode to API + ConfigMap
# so we can register the self-managed worker nodes via an EKS Access Entry
# instead of hand-editing the aws-auth ConfigMap.
# =============================================================================

resource "aws_eks_cluster" "thermos" {
  name     = "${var.project_name}-eks"
  role_arn = data.aws_iam_role.cluster.arn
  # No explicit 'version' - lets AWS use its current default supported
  # version, so this doesn't go stale as EKS deprecates older versions.

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = { Name = "${var.project_name}-eks" }
}

# =============================================================================
# Worker nodes - SELF-MANAGED (Launch Template + Auto Scaling Group)
#
# WHY NOT A MANAGED NODE GROUP (aws_eks_node_group):
# The KodeKloud AWS Playground's IAM policy carries an EXPLICIT DENY on the
# eks:CreateNodegroup action for the lab user, regardless of role names,
# instance types, or Terraform vs. Console vs. CLI. KodeKloud staff have
# confirmed in their community forum that managed node groups cannot be
# created in the playground at all - this is a hard platform restriction,
# not something fixable by changing this config. See
# docs/03-kodekloud-aws-playground-limits.md for sources/details.
#
# The workaround: plain EC2 instances in an Auto Scaling Group, bootstrapped
# via the AL2023 nodeadm NodeConfig mechanism, joined to the cluster via an
# EKS Access Entry (type EC2_LINUX). None of this calls eks:CreateNodegroup,
# so it isn't affected by the deny.
# =============================================================================

# Managed node groups get an instance profile automatically; self-managed
# EC2 instances need one created explicitly to attach AmazonEKSNodeRole.
resource "aws_iam_instance_profile" "node" {
  name = "${var.project_name}-eks-node-profile"
  role = data.aws_iam_role.node.name
}

# EKS-optimized Amazon Linux 2023 AMI, pinned to whatever Kubernetes version
# the cluster actually ends up running (avoids hardcoding a version that goes
# stale). This data source resolves once the cluster's version is known.
#
# NOTE: this uses AL2023, not AL2. AWS stopped publishing new Amazon Linux 2
# EKS-optimized AMIs once AL2023 became the default (AL2 SSM parameters don't
# exist for newer Kubernetes versions and this data source will fail with
# "couldn't find resource" if pointed at the old amazon-linux-2 path).
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${aws_eks_cluster.thermos.version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

resource "aws_launch_template" "node" {
  name_prefix   = "${var.project_name}-eks-node-"
  image_id      = data.aws_ssm_parameter.eks_ami.value
  instance_type = var.node_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.node.arn
  }

  # Reuse the cluster's own security group on the nodes too - this is the
  # standard "cluster security group" pattern, which already has the rules
  # needed for node<->control-plane traffic without managing extra SGs.
  vpc_security_group_ids = [aws_eks_cluster.thermos.vpc_config[0].cluster_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20 # within KodeKloud's 30 GB / GP2-GP3-only limit
      volume_type = "gp3"
    }
  }

  # AL2023 node bootstrap: unlike the old AL2 bootstrap.sh script, AL2023
  # uses "nodeadm", which is configured via a YAML NodeConfig document
  # passed directly as user data (no shell script wrapper). cluster name,
  # API endpoint, CA, and service CIDR must all be supplied explicitly -
  # AL2023 deliberately dropped the old behavior of calling
  # eks:DescribeCluster from inside the instance to fetch these itself.
  user_data = base64encode(<<-EOF
    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      cluster:
        name: ${aws_eks_cluster.thermos.name}
        apiServerEndpoint: ${aws_eks_cluster.thermos.endpoint}
        certificateAuthority: ${aws_eks_cluster.thermos.certificate_authority[0].data}
        cidr: ${aws_eks_cluster.thermos.kubernetes_network_config[0].service_ipv4_cidr}
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                                             = "${var.project_name}-eks-node"
      "kubernetes.io/cluster/${var.project_name}-eks" = "owned"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "node" {
  name                = "${var.project_name}-eks-nodes"
  vpc_zone_identifier = aws_subnet.public[*].id
  desired_capacity    = var.desired_node_count
  min_size            = 1
  max_size            = 3 # KodeKloud AWS Playground EKS node group limit

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-eks-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.project_name}-eks"
    value               = "owned"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Registers AmazonEKSNodeRole as an authorized node identity on the cluster
# (the self-managed-node equivalent of what a managed node group would do
# automatically). Requires access_config.authentication_mode above.
resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.thermos.name
  principal_arn = data.aws_iam_role.node.arn
  type          = "EC2_LINUX"
}

# =============================================================================
# NodePort ingress - REQUIRED for `type: LoadBalancer` Services to be reachable
#
# The EKS-managed "cluster security group" (reused by the worker nodes above)
# only allows traffic between the control plane and the nodes themselves - it
# has NO rule permitting inbound traffic from the internet. Our thermos-frontend
# Service creates a Network Load Balancer in "instance" target mode, which
# forwards connections directly to a node's NodePort (a port Kubernetes
# allocates in the 30000-32767 range) while preserving the original client
# source IP. Without an explicit ingress rule opening that range, the NLB's
# health checks and every real client connection are silently dropped by the
# security group before they ever reach kube-proxy/the pod - the Service gets
# an EXTERNAL-IP, DNS resolves, but every connection times out
# (ERR_CONNECTION_TIMED_OUT), because the packets never arrive.
# =============================================================================
resource "aws_security_group_rule" "nodeport_ingress" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_eks_cluster.thermos.vpc_config[0].cluster_security_group_id
  description       = "Allow NLB to node NodePort traffic for type LoadBalancer Services"
}

# =============================================================================
# ECR repositories - Kubernetes pulls images from here (not from local Docker)
# force_delete lets 'terraform destroy' remove these even with images inside.
# =============================================================================

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project_name}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}
