#########################################################
# variables.tf
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "env" {
  type    = string
  default = "dev"
}
variable "cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}
variable "pub_subnet_count" {
  type    = number
  default = 4
}
variable "pub_cidr_block" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20", "10.0.64.0/20"]
}
variable "pub_availability_zone" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
}
variable "ec2_instance_count" {
  type    = number
  default = 4
}
variable "ec2_instance_type" {
  type    = list(string)
  default = ["t3a.xlarge", "t3a.medium", "t3a.medium", "t3a.medium"]
}
variable "ec2_volume_size" {
  type    = number
  default = 50
}
variable "ec2_volume_type" {
  type    = string
  default = "gp3"
}



