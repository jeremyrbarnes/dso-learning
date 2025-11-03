# main.tf

## 1. AWS Provider and Region Configuration
terraform {
  required_version = "~> 1.13.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.14.1"
    }
  }

  cloud {}
}

# Configure the AWS Provider with your desired region
provider "aws" {
  region = var.aws_region
}

## 2. Data Block to Find the Latest Ubuntu 24.04 AMI
# This searches for the most recent official Canonical AMI for Ubuntu 24.04 (Noble Numbat)
# with the hvm-ssd-gp3-backed-server type (which is what the user specified)
data "aws_ami" "ubuntu_noble" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical's AWS account ID
}

## 3. IAM Role and Instance Profile for Session Manager (SSM)
# Session Manager requires an IAM role with the correct policy attached to the EC2 instance.

# 3a. IAM Role
resource "aws_iam_role" "ssm_role" {
  name = "ec2-ssm-session-manager-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      },
    ],
  })
}

# 3b. Attach the required SSM policy to the role
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 3c. IAM Instance Profile (The resource that gets attached to the EC2 instance)
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ec2-ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

locals {
  org     = "jeremybarnes"
  project = "netflix-clone"
  env     = var.env
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
  count                   = var.pub_subnet_count
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = element(var.pub_cidr_block, count.index)
  availability_zone       = element(var.pub_availability_zone, count.index)
  map_public_ip_on_launch = true

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

  depends_on = [aws_vpc.vpc]
}

resource "aws_security_group" "ssm_only_sg" {
  name        = "ssm-only-access-sg"
  description = "Allow all outbound traffic, no inbound required for SSM"
  vpc_id      = aws_vpc.vpc.id

  # Allow all outbound traffic (Egress)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Ingress (Incoming): No rules needed for Session Manager access.
  # You can add rules here if you need external access (e.g., Jenkins on 8080, Monitoring on 9090, or SSH on 22)
  # Example Ingress for SSH from your home IP:
  # ingress {
  #   description = "SSH from home IP"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["<YOUR_HOME_IP>/32"] # Replace with your public IP address
  # }

  tags = {
    Name = "SSM Only Security Group"
  }
}

## 4. EC2 Instances
# Define the names for the four instances
locals {
  instance_names = [
    "jenkins-server",
    "monitoring-server",
    "kubernetes-master-node",
    "kubernetes-worker-node",
  ]
}

# Create the instances using a for_each loop over the instance_names list
resource "aws_instance" "app_servers" {
  for_each               = toset(local.instance_names)
  ami                    = data.aws_ami.ubuntu_noble.id
  instance_type          = "t2.micro"                  # **CHANGE THIS to your desired instance type**
  subnet_id              = aws_subnet.public-subnet.id # **REQUIRED: Replace with an actual Subnet ID**
  vpc_security_group_ids = toset(aws_security_group.ssm_only_sg.id)
  # key_name             = "my-key-pair" # OPTIONAL: Uncomment and replace with your key pair if needed for SSH access

  # Attach the IAM Instance Profile to enable Session Manager
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name

  tags = {
    Name = each.key # This sets the unique name for each instance
    Role = each.key
  }
}

## 5. Output the Instance IDs
output "instance_ids" {
  description = "IDs of the created EC2 instances"
  value       = { for name, instance in aws_instance.app_servers : name => instance.id }
}


# # backend.tf
# terraform {
#   required_version = "~> 1.13.3"
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 6.14.1"
#     }
#   }

#   cloud {}
# }
# provider "aws" {
#   region = var.aws_region
# }

# ###################################################
# # gather.tf
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"] # Canonical's AWS account ID

#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }

#   filter {
#     name   = "root-device-type"
#     values = ["ebs"]
#   }
# }

# output "ubuntu_ami_id" {
#   value = data.aws_ami.ubuntu.id
# }

# # iam.tf
# resource "aws_iam_role" "ec2_role" {
#   name = "${local.org}-${local.project}-${local.env}-ec2-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Sid    = ""
#         Principal = {
#           Service = "ec2.amazonaws.com"
#         }
#       },
#     ]
#   })

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-ec2-role"
#     Env  = "${local.env}"
#   }
# }

# resource "aws_iam_role_policy_attachment" "custom" {
#   role       = aws_iam_role.ec2_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
# }

# resource "aws_iam_instance_profile" "netflix-clone-ec2-profile" {
#   name = "netflix-clone-ec2-profile"
#   role = aws_iam_role.ec2_role.name
# }

# ##################################################
# # vpc.tf
# locals {
#   org     = "jeremybarnes"
#   project = "netflix-clone"
#   env     = var.env
# }

# resource "aws_vpc" "vpc" {
#   cidr_block           = var.cidr_block
#   instance_tenancy     = "default"
#   enable_dns_hostnames = true
#   enable_dns_support   = true

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-vpc"
#     Env  = "${local.env}"
#   }
# }

# resource "aws_internet_gateway" "igw" {
#   vpc_id = aws_vpc.vpc.id

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-igw"
#     env  = var.env
#   }

#   depends_on = [aws_vpc.vpc]
# }

# resource "aws_subnet" "public-subnet" {
#   count                   = var.pub_subnet_count
#   vpc_id                  = aws_vpc.vpc.id
#   cidr_block              = element(var.pub_cidr_block, count.index)
#   availability_zone       = element(var.pub_availability_zone, count.index)
#   map_public_ip_on_launch = true

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-public-subnet-${count.index + 1}"
#     Env  = var.env
#   }

#   depends_on = [aws_vpc.vpc]
# }

# resource "aws_route_table" "public-rt" {
#   vpc_id = aws_vpc.vpc.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.igw.id
#   }

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-public-route-table"
#     env  = var.env
#   }

#   depends_on = [aws_vpc.vpc]
# }

# resource "aws_security_group" "default-ec2-sg" {
#   name        = "${local.org}-${local.project}-${local.env}-sg"
#   description = "Default Security Group"

#   vpc_id = aws_vpc.vpc.id

#   ingress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"] // It should be specific IP range
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-sg"
#   }
# }

# resource "aws_security_group" "ec2-ssm_https" {
#   name        = "${local.org}-${local.project}-${local.env}-sg-ssm"
#   description = "Allow SSM traffic"
#   vpc_id      = aws_vpc.vpc.id

#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   # egress {
#   #   from_port   = 0
#   #   to_port     = 0
#   #   protocol    = "-1"
#   #   cidr_blocks = ["0.0.0.0/0"]
#   # }
#   tags = {
#     Name = "ssm ingress and egress"
#   }
# }

# #######################################################
# # main.tf
# locals {
#   instance_names = [
#     "jenkins-server",
#     "monitoring-server",
#     "kubernetes-master-node",
#     "kubernetes-worker-node"
#   ]
# }

# resource "aws_instance" "ec2" {
#   count                  = var.ec2_instance_count
#   ami                    = data.aws_ami.ubuntu.id
#   subnet_id              = aws_subnet.public-subnet[count.index].id
#   instance_type          = var.ec2_instance_type[count.index]
#   iam_instance_profile   = aws_iam_instance_profile.netflix-clone-ec2-profile.name
#   vpc_security_group_ids = [aws_security_group.default-ec2-sg.id, aws_security_group.ec2-ssm_https.id]
#   root_block_device {
#     volume_size = var.ec2_volume_size
#     volume_type = var.ec2_volume_type
#   }

#   user_data = <<-EOF
#     #!/bin/bash
#     # Ensure snap is installed (standard on modern Ubuntu, but good practice)
#     apt update -y
#     sudo apt install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
#     sudo systemctl enable amazon-ssm-agent
#     sudo systemctl start amazon-ssm-agent    

#     # Wait a few seconds for the agent to register with the SSM service
#     sleep 30
#   EOF

#   tags = {
#     Name = "${local.org}-${local.project}-${local.env}-${local.instance_names[count.index]}"
#     Env  = "${local.env}"
#   }
# }
