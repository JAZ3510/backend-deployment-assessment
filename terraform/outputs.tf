output "vpc_id" {
  description = "ID of the startuptech VPC"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.backend.dns_name
}

output "bastion_public_ip" {
  description = "Elastic IP of the bastion host"
  value       = aws_eip.bastion.public_ip
}

output "backend_private_ip" {
  description = "Private IP of the backend server"
  value       = aws_instance.backend.private_ip
}

output "mongodb_private_ip" {
  description = "Private IP of the standalone MongoDB server"
  value       = aws_instance.mongodb.private_ip
}
