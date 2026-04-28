# --------------------------------------------------------------------
# Lambda package build
# --------------------------------------------------------------------

resource "null_resource" "lambda_package" {
  triggers = {
    source_hash = filesha256("${path.module}/lambda/run_ansible.py")
  }

  provisioner "local-exec" {
    command = <<-EOF
      rm -rf ${path.module}/lambda_build
      mkdir -p ${path.module}/lambda_build
      cp ${path.module}/lambda/run_ansible.py ${path.module}/lambda_build/
      python3 -m pip install paramiko -t ${path.module}/lambda_build
    EOF
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda_run_ansible.zip"

  depends_on = [null_resource.lambda_package]
}

# --------------------------------------------------------------------
# Store bastion SSH private key in Secrets Manager
# --------------------------------------------------------------------

resource "aws_secretsmanager_secret" "bastion_private_key" {
  name = "${var.project_name}-bastion-private-key"

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "bastion_private_key" {
  secret_id     = aws_secretsmanager_secret.bastion_private_key.id
  secret_string = file(pathexpand(var.bastion_private_key_file_path))
}

# --------------------------------------------------------------------
# IAM role for Lambda
# --------------------------------------------------------------------

resource "aws_iam_role" "run_ansible_lambda" {
  name = "${var.project_name}-run-ansible-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "run_ansible_lambda_basic" {
  role       = aws_iam_role.run_ansible_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "run_ansible_lambda_policy" {
  name = "${var.project_name}-run-ansible-lambda-policy"
  role = aws_iam_role.run_ansible_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.bastion_private_key.arn
      }
    ]
  })
}

# --------------------------------------------------------------------
# Lambda function
# --------------------------------------------------------------------

resource "aws_lambda_function" "run_ansible" {
  function_name = "${var.project_name}-run-ansible"
  role          = aws_iam_role.run_ansible_lambda.arn

  runtime = "python3.12"
  handler = "run_ansible.lambda_handler"

  filename         = "${path.module}/lambda_run_ansible.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_run_ansible.zip")

  timeout     = 900
  memory_size = 512

  environment {
    variables = {
      BASTION_PUBLIC_IP              = aws_instance.bastion.public_ip
      BASTION_PRIVATE_KEY_SECRET_ARN = aws_secretsmanager_secret.bastion_private_key.arn
      ANSIBLE_PROJECT_PATH           = var.ansible_project_path_on_bastion
      AURORA_ENDPOINT                = aws_rds_cluster.postgres.endpoint
      REDIS_ENDPOINT                 = aws_lb.backend.dns_name
    }
  }
}

# --------------------------------------------------------------------
# ASG Lifecycle Hooks
# --------------------------------------------------------------------

resource "aws_autoscaling_lifecycle_hook" "frontend_launch" {
  name                   = "${var.project_name}-frontend-launch-hook"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"

  heartbeat_timeout = 900
  default_result    = "CONTINUE"
}

resource "aws_autoscaling_lifecycle_hook" "backend_launch" {
  name                   = "${var.project_name}-backend-launch-hook"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"

  heartbeat_timeout = 900
  default_result    = "CONTINUE"
}

# --------------------------------------------------------------------
# EventBridge rule for ASG lifecycle events
# --------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "asg_launch_lifecycle" {
  name = "${var.project_name}-asg-launch-lifecycle"

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-launch Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [
        aws_autoscaling_group.frontend.name,
        aws_autoscaling_group.backend.name
      ]
    }
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "asg_launch_lifecycle_lambda" {
  rule      = aws_cloudwatch_event_rule.asg_launch_lifecycle.name
  target_id = "RunAnsibleLambda"
  arn       = aws_lambda_function.run_ansible.arn
}

resource "aws_lambda_permission" "allow_eventbridge_run_ansible" {
  statement_id  = "AllowExecutionFromEventBridgeRunAnsible"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.run_ansible.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.asg_launch_lifecycle.arn
}