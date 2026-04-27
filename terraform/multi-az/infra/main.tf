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
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)

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
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${var.project_name}-public-${local.availability_zones[count.index]}" })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = merge(local.tags, { Name = "${var.project_name}-private-${local.availability_zones[count.index]}" })
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${var.project_name}-igw" })
}





resource "aws_eip" "nat" {
  count      = length(aws_subnet.public)
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = merge(local.tags, { Name = "${var.project_name}-nat-eip-${count.index}" })
}

resource "aws_nat_gateway" "nat" {
  count         = length(aws_subnet.public)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { Name = "${var.project_name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }

  tags = merge(local.tags, { Name = "${var.project_name}-private-rt-${count.index}" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
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
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}




resource "aws_key_pair" "my_key" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_file_path)
}



resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = local.tags
}


resource "aws_lb_target_group" "vote" {
  name     = "${var.project_name}-vote-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200-499"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_target_group" "result" {
  name     = "${var.project_name}-result-tg"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    matcher             = "200-499"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags
}

resource "aws_lb_listener" "vote" {
  load_balancer_arn = aws_lb.web.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote.arn
  }
}

resource "aws_lb_listener" "result" {
  load_balancer_arn = aws_lb.web.arn
  port              = 8081
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.result.arn
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTP traffic (ports 8080, 8081) from the internet to the Application Load Balancer"
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


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.project_name}-alb-sg" })
}

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH access from the internet to the bastion host for administrative access to private instances"
  vpc_id      = aws_vpc.main.id

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

  tags = merge(local.tags, { Name = "${var.project_name}-bastion-sg" })
}

resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-frontend-sg"
  description = "Allow HTTP traffic (ports 8080, 8081) from ALB and SSH access from bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Vote app"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Result app"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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
  description = "Allow Redis traffic from frontend and SSH access from bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from frontend"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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
  description = "Allow PostgreSQL access from frontend and backend, and SSH access from bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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


# --------------------------------------------------------------------
# Launch Template + Auto Scaling Group
# --------------------------------------------------------------------

resource "aws_launch_template" "frontend" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.my_key.key_name

  vpc_security_group_ids = [aws_security_group.frontend.id]

  user_data = base64encode(local.common_user_data)

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.project_name}-frontend" })
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns = [
    aws_lb_target_group.vote.arn,
    aws_lb_target_group.result.arn
  ]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-frontend"
    propagate_at_launch = true
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.my_key.key_name
  associate_public_ip_address = true
  user_data                   = local.common_user_data

  tags = merge(local.tags, {
    Name        = "${var.project_name}-bastion"
    Environment = var.environment
  })
}


resource "aws_instance" "backend" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
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
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = aws_key_pair.my_key.key_name
  user_data              = local.common_user_data

  tags = merge(local.tags, {
    Name        = "${var.project_name}-db"
    Environment = var.environment
  })
}


