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
# ecs 생성
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

resource "aws_launch_configuration" "yotest" {
    name = "ecs-launch-configuration"
    image_id = data.aws_ami.amazon_linux_2023.image_id
    instance_type = "t3.small"
    iam_instance_profile = data.aws_iam_instance_profile.ssm.name

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
