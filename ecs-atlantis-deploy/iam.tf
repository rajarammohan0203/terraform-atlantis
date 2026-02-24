# --- EC2 Instance Profile ---
# Allows EC2 instances to register with ECS
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_instance_role" {
  name               = "atlantis-ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "atlantis-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# --- ECS Task Execution Role ---
# Allows ECS to pull images and fetch secrets from SSM
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "atlantis-ecs-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ssm_secrets" {
  statement {
    effect  = "Allow"
    actions = ["ssm:GetParameters"]
    resources = [
      aws_ssm_parameter.github_token.arn,
      aws_ssm_parameter.webhook_secret.arn
    ]
  }
}

resource "aws_iam_policy" "ssm_secrets_policy" {
  name        = "atlantis-ssm-secrets-policy"
  description = "Allow ECS tasks to read Atlantis secrets"
  policy      = data.aws_iam_policy_document.ssm_secrets.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_ssm_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ssm_secrets_policy.arn
}

# --- ECS Task Role ---
# The role assumed by the Atlantis container itself!
# We give it S3 Full Access for the demo, but in production this should be least-privilege.
resource "aws_iam_role" "ecs_task_role" {
  name               = "atlantis-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3_demo" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" # Modify for production
}
