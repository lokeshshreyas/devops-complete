# =============================================================================
# main.tf — Core Infrastructure Resources
# =============================================================================

# =============================================================================
# Simplified Terraform for KodeKloud AWS Playground
# Single file: VPC + EC2 + Security Group + auto-generated SSH key
# Perfect for DevOps freshers - minimalist infrastructure
#
# v11 changes (see ../CHANGELOG.md for the full list):
#   - Auto-generates a working SSH key pair
#   - Ships the application code straight to the instance via Terraform's
#     "file" provisioner instead of requiring a GitHub push
#   - instance_type is a variable with validation against KodeKloud limits
#   - IMDSv2 enabled for security (http_tokens = required)
# =============================================================================

# =============================================================================
# Variables (all have sensible defaults - freshers can deploy without
# changing anything, but every knob that matters is visible right here)
# =============================================================================

# =============================================================================
# VPC Setup (Minimal: Single AZ, No NAT Gateway)
# =============================================================================

resource "aws_vpc" "thermos" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "learning"
    Project     = var.project_name
  }
}

# Public Subnet (Single AZ: us-east-1a)
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.thermos.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  # Auto-assign public IPs to instances in this subnet
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "thermos" {
  vpc_id = aws_vpc.thermos.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route Table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.thermos.id

  # Route: 0.0.0.0/0 -> Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.thermos.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# SSH Key Pair (auto-generated - no manual .pem file hunting required)
# =============================================================================

# A short random suffix keeps the AWS key pair name unique, so re-deploying
# after an earlier session's key pair wasn't cleaned up won't collide.
resource "random_id" "key_suffix" {
  byte_length = 4
}

resource "tls_private_key" "thermos" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "thermos" {
  key_name   = "${var.project_name}-key-${random_id.key_suffix.hex}"
  public_key = tls_private_key.thermos.public_key_openssh

  tags = {
    Name = "${var.project_name}-key"
  }
}

# Saved locally so you (or scripts/06-ssh.sh) can use it directly.
# `terraform destroy` deletes this file automatically along with everything
# else - nothing lingers on disk after cleanup.
resource "local_file" "private_key_pem" {
  content         = tls_private_key.thermos.private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0600"
}

# =============================================================================
# Security Group (Virtual Firewall)
# =============================================================================

resource "aws_security_group" "thermos" {
  name        = "${var.project_name}-sg"
  description = "Security group for Thermos application"
  vpc_id      = aws_vpc.thermos.id

  # SSH (Port 22) - for remote access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH access"
  }

  # HTTP (Port 80) - Frontend
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for frontend"
  }

  # HTTPS (Port 443) - For future use
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for frontend"
  }

  # Backend API (Port 5000) - For testing/debugging
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Backend API access"
  }

  # Egress: Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# =============================================================================
# EC2 Instance (t3.medium by default - 2 vCPU, 4 GB RAM)
# =============================================================================

# Data source: Get latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance
resource "aws_instance" "thermos" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.thermos.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.thermos.key_name

  # User data script: Runs when instance starts
  user_data = base64encode(file("${path.module}/user_data.sh"))

  # Explicit root volume: gp3, well within KodeKloud's 30 GB / GP2-GP3-only limit
  root_block_device {
    volume_type = "gp3"
    volume_size = 15
    encrypted   = true
  }

  # Instance metadata options (security best practice)
  # NOTE: http_tokens = "required" means IMDSv2 is mandatory.
  # user_data.sh has been updated to use IMDSv2 token-based requests.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring = true # Enable detailed monitoring

  tags = {
    Name        = "${var.project_name}-server"
    Environment = "learning"
    Project     = var.project_name
  }

  # Ship the application code straight to the instance. user_data.sh (running
  # in parallel via cloud-init) waits for these files to arrive before it
  # runs `docker compose up` - see terraform-docker/user_data.sh, step 4.
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.thermos.private_key_pem
    host        = self.public_ip
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ubuntu/thermos"]
  }

  provisioner "file" {
    source      = "${path.module}/../docker-compose.yml"
    destination = "/home/ubuntu/thermos/docker-compose.yml"
  }

  provisioner "file" {
    source      = "${path.module}/../src"
    destination = "/home/ubuntu/thermos/src"
  }

  # Print friendly message
  provisioner "local-exec" {
    command = "echo 'EC2 instance is launching and application files have been uploaded. Docker install + startup takes another 3-5 minutes on t3.medium.'"
  }
}
