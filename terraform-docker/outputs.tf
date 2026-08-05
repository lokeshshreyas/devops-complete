# =============================================================================
# outputs.tf — Output Values
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.thermos.id
}

output "public_subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.thermos.id
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.thermos.id
}

output "ec2_public_ip" {
  description = "Public IP address of EC2 instance"
  value       = aws_instance.thermos.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of EC2 instance"
  value       = aws_instance.thermos.public_dns
}

output "app_url" {
  description = "URL to access Thermos application (wait 3-5 minutes after apply)"
  value       = "http://${aws_instance.thermos.public_ip}"
}

output "ssh_private_key_path" {
  description = "Path to the auto-generated private key, ready to use"
  value       = local_file.private_key_pem.filename
}

output "ssh_command" {
  description = "SSH command to connect to EC2 instance (key is auto-generated, no setup needed)"
  value       = "ssh -i ${local_file.private_key_pem.filename} ubuntu@${aws_instance.thermos.public_ip}"
}

output "api_url" {
  description = "API endpoint URL (for debugging)"
  value       = "http://${aws_instance.thermos.public_ip}:5000/api"
}
