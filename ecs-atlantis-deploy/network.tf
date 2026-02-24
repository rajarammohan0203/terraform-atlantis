data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "atlantis-vpc"
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  # To save costs for this demo, we use public subnets and map public IPs to the EC2 instances.
  # The security groups will prevent direct access to the EC2 instances except through the ALB.
  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Name = "atlantis-vpc"
  }
}

resource "aws_security_group" "alb" {
  name        = "atlantis-alb-sg"
  description = "Allow inbound HTTP traffic from the internet to the ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_instances" {
  name        = "atlantis-ecs-instances-sg"
  description = "Allow inbound traffic from ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Traffic from ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "atlantis" {
  name               = "atlantis-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  tags = {
    Name = "atlantis-alb"
  }
}

resource "aws_lb_target_group" "atlantis" {
  name     = "atlantis-tg"
  port     = 4141
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/healthz"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 6
    interval            = 15
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.atlantis.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.atlantis.arn
  }
}
