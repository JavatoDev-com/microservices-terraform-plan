terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.AWS_REGION
}

locals {
  availability_zones = ["${var.AWS_REGION}a", "${var.AWS_REGION}b"]
}

# VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "ig" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    "Name"        = "${var.environment}-igw"
    "Environment" = var.environment
  }
}

# # Elastic-IP (eip) for NAT
# resource "aws_eip" "nat_eip" {
#   vpc        = true
#   depends_on = [aws_internet_gateway.ig]
# }

# # NAT Gateway
# resource "aws_nat_gateway" "nat" {
#   allocation_id = aws_eip.nat_eip.id
#   subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
#   tags = {
#     Name        = "nat-gateway-${var.environment}"
#     Environment = "${var.environment}"
#   }
# }

# Public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-${element(local.availability_zones, count.index)}-public-subnet"
    Environment = "${var.environment}"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(local.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}-${element(local.availability_zones, count.index)}-private-subnet"
    Environment = "${var.environment}"
  }
}

# Routing tables to route traffic for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}

# Routing tables to route traffic for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}

# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

# Route table associations for both Public & Private Subnets
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

# Public
resource "aws_security_group" "public" {
  name        = "${var.environment}-public-sg"
  description = "Security group for public subnet"
  vpc_id      = aws_vpc.vpc.id
  depends_on = [
    aws_vpc.vpc
  ]

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }

  tags = {
    Environment = "${var.environment}"
  }
}


# Public
resource "aws_security_group" "private" {
  name        = "${var.environment}-private-sg"
  description = "Security group for private subnet"
  vpc_id      = aws_vpc.vpc.id
  depends_on = [
    aws_vpc.vpc
  ]

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }

  tags = {
    Environment = "${var.environment}"
  }
}

resource "aws_instance" "app_server" {
  ami                    = "ami-007855ac798b5175e"
  instance_type          = "t2.micro"
  key_name               = "javatodev-app-key"
  count                  = length(var.private_subnets_cidr)
  subnet_id              = element(aws_subnet.private_subnet.*.id, count.index)
  vpc_security_group_ids = [aws_security_group.private.id]
  tags = {
    name = "app_server"
  }
}

resource "aws_instance" "web_server" {
  ami                    = "ami-007855ac798b5175e"
  instance_type          = "t2.micro"
  key_name               = "javatodev-app-key"
  count                  = length(var.public_subnets_cidr)
  subnet_id              = element(aws_subnet.public_subnet.*.id, count.index)
  vpc_security_group_ids = [aws_security_group.public.id]
  tags = {
    name        = "web_server"
    Environment = "${var.environment}"
  }
}

resource "aws_s3_bucket" "load_balancer_log" {
  bucket        = "${var.environment}-load-balancer-log"
  force_destroy = true
  tags = {
    name        = "${var.environment}-load-balancer-log"
    Environment = "${var.environment}"
  }
}

resource "aws_s3_bucket_policy" "grant_access_to_lb" {
  bucket = "${var.environment}-load-balancer-log"
  policy = data.aws_iam_policy_document.allow_access_from_lb.json
}

data "aws_iam_policy_document" "allow_access_from_lb" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:*"
    ]

    resources = [
      aws_s3_bucket.load_balancer_log.arn,
      "${aws_s3_bucket.load_balancer_log.arn}/*",
    ]
  }
}

resource "aws_lb" "app_load_balancer" {
  name               = "${var.environment}-load-balancer"
  load_balancer_type = "application"
  depends_on = [
    aws_s3_bucket.load_balancer_log
  ]
  security_groups = [aws_security_group.public.id]
  subnets         = [for subnet in aws_subnet.public_subnet : subnet.id]
  access_logs {
    bucket  = "${var.environment}-load-balancer-log"
    prefix  = "logs"
    enabled = true
  }

  tags = {
    name        = "${var.environment}-load-balancer"
    Environment = "${var.environment}"
  }

}

resource "aws_lb_listener" "app_load_balancer" {
  load_balancer_arn = aws_lb.app_load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  depends_on = [
    aws_lb.app_load_balancer
  ]

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Fixed response content"
      status_code  = "200"
    }
  }
}