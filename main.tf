terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "app_ecs_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "app_ecr_repo_policy_data" {
  statement {
    sid    = "new policy"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["123456789012"]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
      "ecr:DeleteRepository",
      "ecr:BatchDeleteImage",
      "ecr:SetRepositoryPolicy",
      "ecr:DeleteRepositoryPolicy", 
    ]
  }
}

locals {
    account_id = data.aws_caller_identity.current.account_id
}

resource "aws_ecr_repository" "app_ecr_repo" {
  name = "app-ecr-repo"

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository_policy" "app_ecr_repo_policy" {
  repository = aws_ecr_repository.app_ecr_repo.name
  policy     = data.aws_iam_policy_document.app_ecr_repo_policy_data.json
}

resource "aws_ecs_cluster" "app_ecs_cluster" {
  name = "app-ecs-cluster"
}

resource "aws_ecs_task_definition" "app_ecs_task" {
  family                   = "app-ecs-task-family"
  container_definitions    = <<DEFINITION
  [
    {
      "name": "app-ecs-task",
      "image": "${aws_ecr_repository.app_ecr_repo.repository_url}/${var.container_image}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 443,
          "hostPort": 443
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # use Fargate as the lauch type
  network_mode             = "awsvpc"    # add the awsvpc network mode as this is required for Fargate
  memory                   = 512         # Specify the memory the container requires
  cpu                      = 256         # Specify the CPU the container requires
  execution_role_arn       = "${aws_iam_role.app_ecs_task_exec_role.arn}"
}

resource "aws_iam_role" "app_ecs_task_exec_role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.app_ecs_assume_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_role_policy" {
  role       = "${aws_iam_role.app_ecs_task_exec_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Reference to default VPC
resource "aws_default_vpc" "default_vpc" {
}

# References to default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-east-1b"
}

resource "aws_alb" "app_load_balancer" {
  name               = "ecs-demo-app-load-balancer"
  load_balancer_type = "application"
  subnets = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}"
  ]

  security_groups = ["${aws_security_group.app_ecs_load_balancer_sg.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "app_ecs_load_balancer_sg" {
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
}

resource "aws_lb_target_group" "target_group" {
  name        = "target-group"
  port        = 443
  protocol    = "HTTPS"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.app_load_balancer.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }

  certificate_arn = "arn:aws:acm:${region}:${local.account_id}:certificate/${var.aws_cm_cert_id}"
}

resource "aws_ecs_service" "app_ecs_service" {
  name            = "app-ecs-service"
  cluster         = "${aws_ecs_cluster.app_ecs_cluster.id}"
  task_definition = "${aws_ecs_task_definition.app_ecs_task.arn}"
  launch_type     = "FARGATE"
  desired_count   = 2

  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}"
    container_name   = "${aws_ecs_task_definition.app_ecs_task.family}"
    container_port   = 443
  }

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    assign_public_ip = true
    security_groups  = ["${aws_security_group.app_ecs_service_sg.id}"]
  }
}

resource "aws_security_group" "app_ecs_service_sg" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.app_ecs_load_balancer_sg.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

