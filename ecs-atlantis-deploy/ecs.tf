# --- CloudWatch Logs ---
resource "aws_cloudwatch_log_group" "atlantis" {
  name              = "/ecs/atlantis"
  retention_in_days = 30
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "atlantis" {
  family                   = "atlantis"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge" # Default for EC2
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  memory = 1024

  volume {
    name      = "atlantis-data"
    host_path = "/mnt/atlantis_data"
  }

  container_definitions = jsonencode([
    {
      name      = "atlantis"
      image     = "runatlantis/atlantis:latest"
      cpu       = 512
      memory    = 900
      essential = true

      portMappings = [
        {
          containerPort = 4141
          hostPort      = 0 # Dynamic port mapping for ALB registration
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ATLANTIS_GH_USER", value = var.github_user },
        { name = "ATLANTIS_REPO_ALLOWLIST", value = var.github_repo_allowlist },
        { name = "ATLANTIS_ATLANTIS_URL", value = "http://${aws_lb.atlantis.dns_name}" },
        { name = "ATLANTIS_PORT", value = "4141" }
      ]

      secrets = [
        {
          name      = "ATLANTIS_GH_TOKEN"
          valueFrom = aws_ssm_parameter.github_token.arn
        },
        {
          name      = "ATLANTIS_GH_WEBHOOK_SECRET"
          valueFrom = aws_ssm_parameter.webhook_secret.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "atlantis-data"
          containerPath = "/home/atlantis/.atlantis"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.atlantis.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# --- ECS Service ---
resource "aws_ecs_service" "atlantis" {
  name            = "atlantis-service"
  cluster         = aws_ecs_cluster.atlantis.id
  task_definition = aws_ecs_task_definition.atlantis.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.atlantis.arn
    container_name   = "atlantis"
    container_port   = 4141
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}
