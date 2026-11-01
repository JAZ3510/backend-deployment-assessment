variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

variable "backend_instance_type" {
  description = "Instance type for the backend server"
  type        = string
  default     = "t3.micro"
}

variable "mongodb_instance_type" {
  description = "Instance type for the MongoDB server"
  type        = string
  default     = "t3.micro"
}

variable "my_ip" {
  description = "Your current public IP in CIDR form (e.g. 203.0.113.10/32). Used to allow SSH to the bastion."
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip, 0))
    error_message = "my_ip must be a valid CIDR block, e.g. 203.0.113.10/32."
  }
}

variable "key_name" {
  description = "Name of an existing EC2 key pair used for SSH access to all instances"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the two public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the two private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}
