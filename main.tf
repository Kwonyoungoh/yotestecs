#####################################
# vpc 생성
resource "aws_vpc" "yotest_vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# 서브넷 생성
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id  = aws_vpc.yotest_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-public-${var.azs[count.index]}"
    public = "on"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.yotest_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.azs[count.index]}"
  }
}

# 인터넷 게이트웨이 생성 및 vpc 연결
resource "aws_internet_gateway" "yotest_ig" {
    vpc_id = aws_vpc.yotest_vpc.id

    tags = {
      Name = "${var.project_name}-internet_gateway"
    }
}

# nat 게이트웨이 생성 및 연결
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_nat_gateway" "yotest_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id = aws_subnet.public[0].id

  tags = {
    Name = "yotest-NAT"
  }
}

# 라우팅테이블 생성
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.yotest_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.yotest_ig.id
  }

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.yotest_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.yotest_nat.id
  }

  tags = {
    Name = "${var.project_name}-private-${var.azs[count.index]}"
  }
}

# 라우팅 테이블 연결
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id       = aws_subnet.public[count.index].id
  route_table_id  = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

#####################################
# ECS 생성
# SSM 연결을 위한 IAM 인스턴스 프로파일
data "aws_iam_instance_profile" "ssm" {
  name = "AmazonSSMRoleForInstancesQuickSetup"
}

resource "aws_ecs_cluster" "yotest" {
    name = "yotest-cluster"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2023-ami-kernel-5.10-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
}

# ECS 인스턴스 보안 그룹
resource "aws_security_group" "ecs_instance_sg" {
  name        = "ecs-instance-security-group"
  description = "Allow traffic from ALB to ECS instances"
  vpc_id      = aws_vpc.yotest_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-instance-sg"
  }
}

resource "aws_launch_configuration" "yotest" {
    name = "ecs-launch-configuration"
    image_id = data.aws_ami.amazon_linux_2023.image_id
    instance_type = "t3.small"
    iam_instance_profile = data.aws_iam_instance_profile.ssm.name
    security_groups = [aws_security_group.ecs_instance_sg.id]

    # ECS 에이전트 설정
    user_data = <<-EOF
                    #!/bin/bash
                    echo ECS_CLUSTER=${aws_ecs_cluster.yotest.name} >> /etc/ecs/ecs.config
                    dnf install -y aws-cli
                    EOF

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_autoscaling_group" "yotest_asg" {
    launch_configuration = aws_launch_configuration.yotest.id
    min_size = 1
    max_size = 2
    desired_capacity = 1

    vpc_zone_identifier = [for s in aws_subnet.private : s.id]

    tag {
        key                 = "Name"
        value               = "ECS Instance - yotest"
        propagate_at_launch = true
    }
}

#####################################
# ALB
# ALB 보안 그룹 설정
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Allow HTTPS traffic to ALB"
  vpc_id      = aws_vpc.yotest_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}


# Application Load Balancer 생성
resource "aws_lb" "yotest_alb" {
  name               = "yotest-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = {
    Name = "yotest-ALB"
  }
}

# HTTPS 리스너 설정
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.yotest_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.yotest.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.yotest_tg.arn
  }
}

resource "aws_lb_listener_rule" "yotest" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.yotest_tg.arn
  }

  condition {
    host_header {
      values = ["yotest.link", "www.yotest.link"]
    }
  }
}

# 타겟그룹 생성
resource "aws_lb_target_group" "yotest_tg" {
  name     = "yotest-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.yotest_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name = "yotest-tg"
  }
}

#####################################
# RDS
resource "aws_db_instance" "yotest_rds" {
  allocated_storage    = 10
  db_name              = "yotestdb"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = var.rds_username
  password             = var.rds_secret
  parameter_group_name = "default.mysql5.7"
  db_subnet_group_name = aws_db_subnet_group.yotest_rds.name
  vpc_security_group_ids = [aws_security_group.yotest_rds.id]

  publicly_accessible = false 
  skip_final_snapshot  = true
}

resource "aws_db_subnet_group" "yotest_rds" {
  name       = "my-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_security_group" "yotest_rds" {
  name        = "rds-public-access"
  description = "Allow only inbound traffic from ECS security group on port 3306"
  vpc_id      = data.aws_vpc.default.id 

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_instance_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}