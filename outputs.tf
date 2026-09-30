output "ec2_instance_id" {
  description = "The ID of the AWX EC2 instance."
  value       = aws_instance.awx_server.id
}

output "aws_region" {
  description = "The AWS region containing the AWX EC2 instance."
  value       = var.aws_region
}

output "public_ip" {
  description = "The public IP of the AWX EC2 instance."
  value       = aws_instance.awx_server.public_ip
}

output "public_dns" {
  description = "The public DNS name of the AWX EC2 instance."
  value       = aws_instance.awx_server.public_dns
}

output "private_key_pem" {
  description = "The private key in PEM format"
  value       = tls_private_key.awx_server_tls_private_key.private_key_pem
  sensitive   = true
}

