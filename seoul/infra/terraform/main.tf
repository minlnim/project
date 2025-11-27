terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket = "terraform-s3-cheonsangyeon"
    key    = "seoul/portal/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

provider "aws" {
  region = var.aws_region
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Wait for EKS cluster to be ready before configuring providers
resource "null_resource" "wait_for_cluster" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "echo EKS cluster is ready"
  }
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      try(module.eks.cluster_name, "dummy"),
      "--region",
      var.aws_region
    ]
  }
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    host                   = try(module.eks.cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        try(module.eks.cluster_name, "dummy"),
        "--region",
        var.aws_region
      ]
    }
  }
}

# Import CloudFront state
data "terraform_remote_state" "cloudfront" {
  backend = "s3"
  config = {
    bucket = "terraform-s3-cheonsangyeon"
    key    = "terraform/global-cloudfront/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# Import Seoul state
data "terraform_remote_state" "seoul" {
  backend = "s3"
  config = {
    bucket = "terraform-s3-cheonsangyeon"
    key    = "terraform/seoul/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# Import Tokyo state
data "terraform_remote_state" "tokyo" {
  backend = "s3"
  config = {
    bucket = "terraform-s3-cheonsangyeon"
    key    = "terraform/tokyo/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

locals {
  project = "seoul-portal"
  env     = "seoul"

  tags = {
    Project = local.project
    Env     = local.env
  }

  # 기존 Seoul 인프라에서 VPC 및 서브넷 정보 가져오기
  vpc_id             = data.terraform_remote_state.seoul.outputs.seoul_vpc_id
  private_subnet_ids = data.terraform_remote_state.seoul.outputs.seoul_beanstalk_subnet_ids
  db_subnet_ids      = data.terraform_remote_state.seoul.outputs.seoul_beanstalk_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.seoul.outputs.seoul_beanstalk_subnet_ids  # ELB용
  
  # CloudFront 정보 (remote state에서 가져오기)
  cloudfront_domain = try(data.terraform_remote_state.cloudfront.outputs.cloudfront_domain_name, "")
  cloudfront_id     = try(data.terraform_remote_state.cloudfront.outputs.cloudfront_distribution_id, var.existing_cloudfront_id)
}

########################################
# 1. Cognito User Pool (Auth)
########################################

resource "aws_cognito_user_pool" "seoul" {
  name = "${local.project}-${local.env}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_uppercase = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_client" "seoul_spa" {
  name         = "${local.project}-${local.env}-spa-client"
  user_pool_id = aws_cognito_user_pool.seoul.id

  generate_secret = false

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  supported_identity_providers = ["COGNITO"]

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]
}

resource "aws_cognito_user_pool_domain" "seoul" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.seoul.id
}

# Test users for development
resource "aws_cognito_user" "test_users" {
  for_each = var.test_users

  user_pool_id = aws_cognito_user_pool.seoul.id
  username     = each.value.email

  attributes = {
    email          = each.value.email
    email_verified = "true"
    name           = each.value.name
    family_name    = each.value.family_name
  }

  password = each.value.password

  lifecycle {
    ignore_changes = [
      password,
      attributes
    ]
  }
}

########################################
# 3. RDS (직원/공지/조직/결재 데이터)
########################################

# 기존 Aurora 인스턴스 정보 가져오기
data "aws_db_instance" "existing" {
  db_instance_identifier = var.existing_rds_instance_identifier
}

# Local values for DB connection (기존 Aurora 사용)
locals {
  db_endpoint          = data.aws_db_instance.existing.address
  db_port              = data.aws_db_instance.existing.port
  db_security_group_id = data.aws_db_instance.existing.vpc_security_groups[0]
}

########################################
# 3-1. Lambda for RDS Database Initialization
########################################

# Lambda execution role for DB initialization
resource "aws_iam_role" "db_init_lambda" {
  name = "${local.project}-${local.env}-db-init-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "db_init_lambda_vpc" {
  role       = aws_iam_role.db_init_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "db_init_lambda_basic" {
  role       = aws_iam_role.db_init_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda security group
resource "aws_security_group" "db_init_lambda" {
  name        = "${local.project}-${local.env}-db-init-lambda-sg"
  description = "Security group for DB initialization Lambda"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# Lambda function for DB initialization
data "archive_file" "db_init_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/db-init"
  output_path = "${path.module}/lambda/db-init.zip"
}

resource "aws_lambda_function" "db_init" {
  filename         = data.archive_file.db_init_lambda.output_path
  function_name    = "${local.project}-${local.env}-db-init"
  role            = aws_iam_role.db_init_lambda.arn
  handler         = "index.lambda_handler"
  source_code_hash = data.archive_file.db_init_lambda.output_base64sha256
  runtime         = "python3.11"
  timeout         = 300

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.db_init_lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = local.db_endpoint
      DB_PORT     = tostring(local.db_port)
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
    }
  }

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.db_init_lambda_vpc,
    aws_iam_role_policy_attachment.db_init_lambda_basic
  ]
}

# Allow Lambda to access RDS
resource "aws_security_group_rule" "rds_from_lambda" {
  type                     = "ingress"
  from_port                = local.db_port
  to_port                  = local.db_port
  protocol                 = "tcp"
  security_group_id        = local.db_security_group_id
  source_security_group_id = aws_security_group.db_init_lambda.id
  description              = "Allow DB init Lambda to access RDS"
}

# Invoke Lambda to initialize database
resource "null_resource" "invoke_db_init" {
  triggers = {
    lambda_version = aws_lambda_function.db_init.version
    always_run     = timestamp()
  }

  provisioner "local-exec" {
    command = "aws lambda invoke --function-name ${aws_lambda_function.db_init.function_name} --region ${var.aws_region} --payload '{}' response.json"
  }

  depends_on = [
    aws_lambda_function.db_init,
    aws_security_group_rule.rds_from_lambda
  ]
}

########################################
# 4. ECR (백엔드 컨테이너 이미지)
########################################

resource "aws_ecr_repository" "backend" {
  name                 = "${local.project}-${local.env}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${local.project}-${local.env}-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = local.tags
}

########################################
# 5. NLB (Backend Entry for API GW → EKS)
########################################

resource "aws_security_group" "vpc_link" {
  name        = "${local.project}-${local.env}-vpc-link-sg"
  description = "Security group for API Gateway VPC Link"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "seoul-vpc-link-sg"
  })
}

resource "aws_lb" "nlb" {
  name               = "${local.project}-${local.env}-nlb"
  load_balancer_type = "network"
  internal           = true
  subnets            = local.private_subnet_ids

  tags = local.tags
}

resource "aws_lb_target_group" "backend" {
  name        = "${local.project}-${local.env}-tg"
  port        = var.backend_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = local.vpc_id

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }

  tags = local.tags
}

resource "aws_lb_listener" "backend" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.backend_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

########################################
# 6. API Gateway HTTP API + VPC Link + JWT Authorizer
########################################

resource "aws_apigatewayv2_vpc_link" "this" {
  name               = "${local.project}-${local.env}-vpc-link"
  subnet_ids         = local.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]

  tags = local.tags
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "${local.project}-${local.env}-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    expose_headers = ["*"]
    max_age = 300
  }

  tags = local.tags
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id          = aws_apigatewayv2_api.http_api.id
  authorizer_type = "JWT"
  name            = "cognito-jwt-authorizer"

  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer = "https://cognito-idp.ap-northeast-2.amazonaws.com/${aws_cognito_user_pool.seoul.id}"
    audience = [
      aws_cognito_user_pool_client.seoul_spa.id
    ]
  }
}

resource "aws_apigatewayv2_integration" "backend" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"

  # NLB Listener ARN 사용 (VPC Link 연결)
  integration_uri = aws_lb_listener.backend.arn

  connection_type = "VPC_LINK"
  connection_id   = aws_apigatewayv2_vpc_link.this.id

  payload_format_version = "1.0"
}

# 1) 로그인 엔드포인트: POST /auth/login (무인증)
resource "aws_apigatewayv2_route" "auth_login" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /auth/login"

  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "NONE"
}

# 2) OPTIONS 요청: OPTIONS /api/{proxy+} (무인증 - CORS 프리플라이트)
resource "aws_apigatewayv2_route" "api_options" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "OPTIONS /api/{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorization_type = "NONE"
}

# 3) 보호된 API: ANY /api/{proxy+} (JWT 필요)
resource "aws_apigatewayv2_route" "api_proxy" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /api/{proxy+}"

  target             = "integrations/${aws_apigatewayv2_integration.backend.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  tags = local.tags
}

########################################
# 7. Kubernetes ConfigMap for Backend
########################################

# GitHub Actions가 kubectl apply로 배포하므로 Terraform에서는 제거
# resource "kubernetes_config_map" "backend" {
#   metadata {
#     name      = "backend-config"
#     namespace = "default"
#   }

#   data = {
#     DB_HOST              = local.db_endpoint
#     DB_PORT              = tostring(local.db_port)
#     DB_NAME              = var.db_name
#     DB_USER              = var.db_username
#     COGNITO_REGION       = var.aws_region
#     COGNITO_USER_POOL_ID = aws_cognito_user_pool.seoul.id
#     COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.seoul_spa.id
#     API_PORT             = "8080"
#   }

#   depends_on = [
#     null_resource.wait_for_cluster
#   ]
# }

# resource "kubernetes_secret" "backend" {
#   metadata {
#     name      = "backend-secret"
#     namespace = "default"
#   }

#   data = {
#     DB_PASSWORD = var.db_password
#   }

#   type = "Opaque"

#   depends_on = [
#     module.eks
#   ]
# }

########################################
# 8. Kubernetes Deployment for Backend
########################################

# GitHub Actions가 kubectl apply로 배포하므로 Terraform에서는 제거
# resource "kubernetes_deployment" "backend" {
#   metadata {
#     name      = "backend"
#     namespace = "default"
#     labels = {
#       app = "backend"
#     }
#   }

#   wait_for_rollout = false

#   spec {
#     replicas = 2

#     selector {
#       match_labels = {
#         app = "backend"
#       }
#     }

#     template {
#       metadata {
#         labels = {
#           app = "backend"
#         }
#       }

#       spec {
#         container {
#           name  = "backend"
#           image = "${aws_ecr_repository.backend.repository_url}:latest"
#           image_pull_policy = "IfNotPresent"

#           port {
#             container_port = 8080
#             name          = "http"
#           }

#           env {
#             name = "DB_HOST"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "DB_HOST"
#               }
#             }
#           }

#           env {
#             name = "DB_PORT"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "DB_PORT"
#               }
#             }
#           }

#           env {
#             name = "DB_NAME"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "DB_NAME"
#               }
#             }
#           }

#           env {
#             name = "DB_USER"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "DB_USER"
#               }
#             }
#           }

#           env {
#             name = "DB_PASSWORD"
#             value_from {
#               secret_key_ref {
#                 name = kubernetes_secret.backend.metadata[0].name
#                 key  = "DB_PASSWORD"
#               }
#             }
#           }

#           env {
#             name = "COGNITO_REGION"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "COGNITO_REGION"
#               }
#             }
#           }

#           env {
#             name = "COGNITO_USER_POOL_ID"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "COGNITO_USER_POOL_ID"
#               }
#             }
#           }

#           env {
#             name = "COGNITO_CLIENT_ID"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "COGNITO_CLIENT_ID"
#               }
#             }
#           }

#           env {
#             name = "API_PORT"
#             value_from {
#               config_map_key_ref {
#                 name = kubernetes_config_map.backend.metadata[0].name
#                 key  = "API_PORT"
#               }
#             }
#           }

#           resources {
#             requests = {
#               memory = "256Mi"
#               cpu    = "200m"
#             }
#             limits = {
#               memory = "512Mi"
#               cpu    = "500m"
#             }
#           }

#           liveness_probe {
#             http_get {
#               path = "/health"
#               port = 8080
#             }
#             initial_delay_seconds = 30
#             period_seconds        = 10
#           }

#           readiness_probe {
#             http_get {
#               path = "/health"
#               port = 8080
#             }
#             initial_delay_seconds = 10
#             period_seconds        = 5
#           }
#         }
#       }
#     }
#   }

#   depends_on = [
#     kubernetes_config_map.backend,
#     kubernetes_secret.backend,
#     aws_ecr_repository.backend
#   ]
# }

########################################
# 9. Kubernetes Service for Backend
########################################

# GitHub Actions가 kubectl apply로 배포하므로 Terraform에서는 제거
# resource "kubernetes_service" "backend" {
#   metadata {
#     name      = "backend"
#     namespace = "default"
#     labels = {
#       app = "backend"
#     }
#   }

#   spec {
#     selector = {
#       app = "backend"
#     }

#     port {
#       port        = 8080
#       target_port = 8080
#       protocol    = "TCP"
#       name        = "http"
#     }

#     type = "ClusterIP"
#   }

#   depends_on = [
#     kubernetes_deployment.backend
#   ]
# }

