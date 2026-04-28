variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "voting-project-ha"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets"
  type        = list(string)
  default     = ["10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnet"
  type        = list(string)
  default     = ["10.30.10.0/24", "10.30.20.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "lab"
}


variable "public_key_file_path" {
  description = "Path of public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}


variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}


variable "db_password" {
  type    = string
  default = "postgres"
}

variable "bastion_private_key_file_path" {
  description = "Private SSH key path for Lambda to SSH into bastion"
  type        = string
}

variable "ansible_project_path_on_bastion" {
  description = "Path of project repo on bastion"
  type        = string
  default     = "/home/ubuntu/ironhack-project-1"
}