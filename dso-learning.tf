# backend.tf
terraform {
  required_version = "~> 1.13.3"
  required_providers {
    aws = {
      source ="hashicorp/aws"
      version = "~> 6.14.1"
    }
  }

  cloud {}
}
provider "aws" {
  region = var.aws_region
}

###################################################
# gather.tf
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*",
      "ubuntu/images/hvm/ubuntu-noble-24.04-amd64-server-*",
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amg64-*",
      "ubuntu/images/hvm-ebs-gp3/ubuntu-noble-24.04-amd64-server-*"
    ]
  }

  owners = ["099720109477"]
}

# iam.tf
resource "aws_iam_role" "role" {
  name = "${local.org}-${local.project}-${local.env}-ssm-iam-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-ssm-iam-role"
    Env  = "${local.env}"
  }
}

##################################################
# vpc.tf
locals {
  org      = "aman"
  project  = "netflix-clone"
  env      = var.env
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-vpc"
    Env  = "${local.env}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-igw"
    env  = var.env
  }

  depends_on = [aws_vpc.vpc]
}

resource "aws_subnet" "public-subnet" {
  count                    = var.pub_subnet_count
  vpc_id                   = aws_vpc.vpc.id
  cidr_block               = element(var.pub_cidr_block, count.index)
  availability_zone        = element(var.pub_availability_zone, count.index)
  map_public_ip_on_launch  = true

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-public-subnet-${count.index + 1}"
    Env  = var.env
  }

  depends_on = [aws_vpc.vpc]
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.vpc.id

  route { 
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-public-route-table"
    env  = var.env
  }

  depends_on = aws_vpc.vpc.id
}

resource "aws_security_group" "default-ec2-sg" {
  name        = "${local.org}-${local.project}-${local.env}-sg"
  description = "Default Security Group"

  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port     = 0
    to_port       = 0
    protocol      = "-1"
    cidr_blocks   = ["0.0.0.0/0"] // It should be specific IP range
  }

  egress {
    from_port     = 0
    to_port       = 0
    protocol      = "-1"
    cidr_blocks   = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-sg"
  }
}

#######################################################
# main.tf
locals {
  instance_names = [
    "jenkins-server",
    "monitoring-server",
    "kubernetes-master-node",
    "kubernetes-worker-node"
  ]
}

resource "aws_instance" "ec2" {
  count                    = var.ec2_instance_count
  ami                      = data.aws_ami.ubuntu.id
  subnet_id                = aws_subnet.public-subnet[count.index].id
  instance_type            = var.ec2_instance_type[count.index]
  iam_instance_profile     = aws_iam_instance_profile.iam-instance-profile.name
  vpc_security_group_ids   = [aws_security_group.default-ec2-sg.id]
  root_block_device {
    volume_size = var.ec2_volume_size
    volume_type = var.ec2_volume_type
  }

  tags = {
    Name = "${local.org}-${local.project}-${local-env}-${local.instance_names[count.index]}"    
    Env  = "${local.env}"
  }
}

#########################################################
# variables.tf
variable "aws_region" {
  type       = string
  default    = "us-east-1"
}
variable "env" {
  type       = string
  default    = "dev"
}
variable "cidr_block" {
  type       = string
  default    = "10.0.0.0/16"
}
variable "pub_subnet_count" {
  type       = number
  default    = 4
}
variable "pub_cidr_block" {
  type       = list(string)
  default    = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20", "10.0.64.0/20"]
}
variable "pub_availability_zone" {
  type       = list(string)
  default    = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
}
variable "ec2_instance_count" {
  type       = number
  default    = 4
}
variable "ec2_instance_type" {
  type       = list(string)
  default    = ["t3a.xlarge", "t3a.medium", "t3a.medium", "t3a.medium"]
}
variable "ec2_volume_size" {
  type       = number
  default    = 50
}
variable "ec2_volume_type" {
  type       = string
  default    = "gp3"
}


 
