data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}


locals {
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }

  common_user_data = <<-EOF
  #!/bin/bash
  set -eux

  apt-get update -y
  apt-get install -y python3 python3-pip

  # optional but useful for debugging
  apt-get install -y iputils-ping netcat-openbsd curl

EOF
}


resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.project_name}-public-subnet" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.availability_zone

  tags = merge(local.tags, { Name = "${var.project_name}-private-subnet" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${var.project_name}-igw" })
}

resource "aws_eip" "eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = merge(local.tags, { Name = "${var.project_name}-elastic-ip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]

  tags = merge(local.tags, { Name = "${var.project_name}-nat" })
}


resource "aws_route_table" "private" {
  tags   = merge(local.tags, { Name = "${var.project_name}-private-route-table" })
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags, { Name = "${var.project_name}-public-route-table" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}



resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-frontend-sg"
  description = "Allow HTTP and SSH inbound to frontend machine"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Vote app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Result app"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.project_name}-frontend-sg" })
}

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Allow SSH and HTTP from frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from frontend"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "SSH from frontend"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.project_name}-backend-sg" })
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow SSH from frontend and PostgreSQL from backend and frontend"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from frontend"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "Allow db access to frontend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "Allow db access to backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.project_name}-db-security-group" })

}

resource "aws_key_pair" "my_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_file_path)
}


resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  key_name                    = aws_key_pair.my_key.key_name
  associate_public_ip_address = true
  user_data                   = local.common_user_data

  tags = merge(local.tags, {
    Name        = "${var.project_name}-frontend"
    Environment = var.environment
  })
}



resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.backend.id]
  key_name               = aws_key_pair.my_key.key_name
  user_data              = local.common_user_data

  tags = merge(local.tags, {
    Name        = "${var.project_name}-backend"
    Environment = var.environment
  })
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.my_key.key_name
  user_data              = local.common_user_data

  tags = merge(local.tags, {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  })
}