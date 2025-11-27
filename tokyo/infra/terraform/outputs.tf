########################################
# Tokyo Portal – Outputs
########################################

# Cognito
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.tokyo.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito SPA Client ID"
  value       = aws_cognito_user_pool_client.tokyo_spa.id
}

output "cognito_domain_url" {
  description = "Cognito Hosted UI 도메인 URL"
  value       = "https://${aws_cognito_user_pool_domain.tokyo.domain}.auth.ap-northeast-1.amazoncognito.com"
}

output "test_users_info" {
  description = "생성된 테스트 사용자 목록"
  value = {
    for key, user in aws_cognito_user.test_users : key => {
      username   = user.username
      email      = user.attributes["email"]
      name       = "${user.attributes["family_name"]}${user.attributes["name"]}"
      department = var.test_users[key].department
      position   = var.test_users[key].position
    }
  }
}

# RDS
output "db_endpoint" {
  description = "백엔드에서 접속할 RDS 엔드포인트"
  value       = local.db_endpoint
}

# ECR
output "backend_ecr_repo_url" {
  description = "백엔드 Docker 이미지 푸시용 ECR 리포지토리 URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repo_url" {
  description = "프론트엔드 Docker 이미지 푸시용 ECR 리포지토리 URL"
  value       = aws_ecr_repository.frontend.repository_url
}

# ArgoCD
output "argocd_server_url" {
  description = "ArgoCD 서버 외부 접속 URL"
  value       = var.enable_argocd ? "https://${try(data.kubernetes_service.argocd_server[0].status[0].load_balancer[0].ingress[0].hostname, "pending")}" : "ArgoCD not enabled"
}

output "argocd_admin_password" {
  description = "ArgoCD 초기 admin 비밀번호 (kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
  value       = "Run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  sensitive   = false
}

# NLB
output "nlb_dns_name" {
  description = "API Gateway VPC Link가 호출할 NLB DNS 이름"
  value       = aws_lb.nlb.dns_name
}

output "nlb_arn" {
  description = "NLB ARN (API Gateway private integration용)"
  value       = aws_lb.nlb.arn
}

# API Gateway
output "api_gateway_http_api_endpoint" {
  description = "프론트엔드에서 API_BASE로 사용할 HTTP API 엔드포인트"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

# ========================================
# 배포 스크립트용 Outputs
# ========================================

output "aws_account_id" {
  description = "AWS 계정 ID"
  value       = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS 리전"
  value       = var.aws_region
}

output "ecr_repository_url" {
  description = "ECR 레포지토리 전체 URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_backend_image" {
  description = "Backend ECR 이미지 전체 경로"
  value       = "${aws_ecr_repository.backend.repository_url}:latest"
}

output "ecr_frontend_image" {
  description = "Frontend ECR 이미지 전체 경로"
  value       = "${aws_ecr_repository.frontend.repository_url}:latest"
}

output "rds_endpoint" {
  description = "RDS 엔드포인트 (ConfigMap용)"
  value       = local.db_endpoint
}

output "api_gateway_url" {
  description = "API Gateway 엔드포인트 URL"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "cognito_client_id" {
  description = "Cognito Client ID (ConfigMap용)"
  value       = aws_cognito_user_pool_client.tokyo_spa.id
}

output "nlb_target_group_arn" {
  description = "NLB 타겟 그룹 ARN (노드 등록용)"
  value       = aws_lb_target_group.backend.arn
}


