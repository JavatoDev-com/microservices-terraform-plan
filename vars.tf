variable "aws_region" {
  default = "us-east-1"
}

variable "environment" {
  default = "javatodev-dev"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "CIDR block of the vpc"
}

variable "public_subnets_cidr" {
  type        = list(any)
  default     = ["10.0.0.0/20", "10.0.128.0/20"]
  description = "CIDR block for Public Subnet"
}

variable "private_subnets_cidr" {
  type        = list(any)
  default     = ["10.0.16.0/20", "10.0.144.0/20"]
  description = "CIDR block for Private Subnet"
}

variable "availability_zones" {
  type = list(any)
  default = [
    "us-east-1a",
    "us-east-1b"
  ]
  description = "AZ in which all the resources will be deployed"
}