terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "MuchTodo"
      Environment = "assessment"
      ManagedBy   = "terraform"
    }
  }
}

############################
# Data sources
############################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent        = true
  owners             = ["amazon"]
  include_deprecated = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

############################
# Networking
############################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "startuptech-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "startuptech-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "startuptech-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "startuptech-private-${count.index + 1}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "startuptech-nat-eip"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "startuptech-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "startuptech-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "startuptech-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################
# Security groups
############################

resource "aws_security_group" "alb" {
  name        = "startuptech-alb-sg"
  description = "ALB: HTTP/HTTPS from anywhere"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "startuptech-alb-sg"
  }
}

resource "aws_security_group" "bastion" {
  name        = "startuptech-bastion-sg"
  description = "Bastion: SSH from my IP only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "startuptech-bastion-sg"
  }
}

resource "aws_security_group" "backend" {
  name        = "startuptech-backend-sg"
  description = "Backend: 8080 from ALB, SSH from bastion"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "startuptech-backend-sg"
  }
}

resource "aws_security_group" "mongodb" {
  name        = "startuptech-mongodb-sg"
  description = "MongoDB: 27017 from backend only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "startuptech-mongodb-sg"
  }
}

# ALB
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Bastion
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from my IP"
  cidr_ipv4         = var.my_ip
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Backend
resource "aws_vpc_security_group_ingress_rule" "backend_app" {
  security_group_id            = aws_security_group.backend.id
  description                  = "App port from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "backend_ssh" {
  security_group_id            = aws_security_group.backend.id
  description                  = "SSH from bastion"
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "backend_all" {
  security_group_id = aws_security_group.backend.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# MongoDB
resource "aws_vpc_security_group_ingress_rule" "mongodb_from_backend" {
  security_group_id            = aws_security_group.mongodb.id
  description                  = "MongoDB from backend"
  referenced_security_group_id = aws_security_group.backend.id
  from_port                    = 27017
  to_port                      = 27017
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "mongodb_all" {
  security_group_id = aws_security_group.mongodb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

############################
# EC2 instances
############################

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public[0].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "startuptech-bastion"
  }
}

resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name = "startuptech-bastion-eip"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_instance" "backend" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.backend_instance_type
  subnet_id              = aws_subnet.private[0].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.backend.id]
  user_data              = file("${path.module}/user_data/backend_setup.sh")

  # User data needs outbound internet via the NAT gateway
  depends_on = [aws_nat_gateway.nat, aws_route_table_association.private]

  tags = {
    Name = "startuptech-backend"
  }
}

resource "aws_instance" "mongodb" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.mongodb_instance_type
  subnet_id              = aws_subnet.private[1].id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.mongodb.id]
  user_data              = file("${path.module}/user_data/mongodb_setup.sh")

  depends_on = [aws_nat_gateway.nat, aws_route_table_association.private]

  tags = {
    Name = "startuptech-mongodb"
  }
}

############################
# Application Load Balancer
############################

resource "aws_lb" "backend" {
  name               = "startuptech-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "startuptech-alb"
  }
}

resource "aws_lb_target_group" "backend" {
  name     = "startuptech-backend-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "startuptech-backend-tg"
  }
}

resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = aws_instance.backend.id
  port             = 8080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
