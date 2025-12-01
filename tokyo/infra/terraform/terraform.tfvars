# Tokyo Portal – terraform.tfvars 예시

# ===== AWS 계정 =====
aws_account_id = "150502622488"

# ===== 네트워크 =====
# VPC를 새로 생성하려면 vpc_id를 빈 문자열로 설정
vpc_id   = ""
vpc_cidr = "30.0.0.0/16"

# VPC를 새로 생성하면 아래 값들은 무시됨 (자동 생성)
private_subnet_ids = []
db_subnet_ids      = []

# ===== Cognito =====
cognito_domain_prefix = "corp-portal-tokyo-demo"

# 로그인/로그아웃 URL (API Gateway 도메인으로 설정 예정)
cognito_callback_urls = [
  "http://localhost:3000/callback"
]

cognito_logout_urls = [
  "http://localhost:3000/"
]

# ===== CORS =====
cors_allowed_origins = [
  "http://localhost:3000"
]

# ===== 기존 Aurora RDS 사용 =====
existing_rds_instance_identifier = "aurora-global-tokyo-reader1"

# RDS 데이터베이스 설정
db_username = "admin"
db_password = "AdminPassword123!"
db_name     = "corpportal"

# 테스트 사용자 목록 (조직도 데이터 포함)
test_users = {
  "ceo" = {
    email       = "ceo@company.com"
    password    = "TempPass123!"
    name        = "홍"
    family_name = "길동"
    department  = "경영진"
    position    = "대표이사"
    phone       = "010-1234-5678"
  }
  "cto" = {
    email       = "cto@company.com"
    password    = "TempPass123!"
    name        = "김"
    family_name = "철수"
    department  = "기술본부"
    position    = "기술이사"
    phone       = "010-2345-6789"
  }
  "manager1" = {
    email       = "manager1@company.com"
    password    = "TempPass123!"
    name        = "이"
    family_name = "영희"
    department  = "개발팀"
    position    = "팀장"
    phone       = "010-3456-7890"
  }
  "developer1" = {
    email       = "dev1@company.com"
    password    = "TempPass123!"
    name        = "박"
    family_name = "민수"
    department  = "개발팀"
    position    = "선임개발자"
    phone       = "010-4567-8901"
  }
  "developer2" = {
    email       = "dev2@company.com"
    password    = "TempPass123!"
    name        = "최"
    family_name = "지혜"
    department  = "개발팀"
    position    = "주임개발자"
    phone       = "010-5678-9012"
  }
  "hr_manager" = {
    email       = "hr@company.com"
    password    = "TempPass123!"
    name        = "정"
    family_name = "수현"
    department  = "인사팀"
    position    = "팀장"
    phone       = "010-6789-0123"
  }
}

# ===== Backend / RDS =====
backend_port = 8080

db_engine            = "postgres"
db_engine_version    = "14.20"
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20
db_port              = 5432

# ===== ArgoCD =====
# GitOps 배포를 사용하려면 true로 설정
# 주의: EKS 클러스터가 생성된 후에만 true로 설정하세요
enable_argocd = true

# ArgoCD 도메인 (선택사항)
argocd_domain = "" # 예: "argocd.example.com"

# GitHub Repository 설정
argocd_repo_url     = "https://github.com/minlnim/project.git"
argocd_repo_branch  = "main"
argocd_backend_path = "tokyo/k8s/base"

# Private Repository 접근 (필요시)
argocd_repo_username = ""
argocd_repo_password = ""

# ===== CloudFront =====
# 기존 CloudFront Distribution ID (빈 문자열이면 새로 생성하지 않음)
existing_cloudfront_id = "E152R78VFY6VWL"
