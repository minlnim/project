########################################
# ArgoCD Installation & Configuration
########################################

# ArgoCD Namespace
resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name = "argocd"
  }

  depends_on = [module.eks, null_resource.wait_for_cluster]
}

# ArgoCD Helm Release
resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd[0].metadata[0].name
  version    = "5.51.6"
  
  timeout       = 900  # 15분으로 증가
  wait          = true
  wait_for_jobs = true
  
  # 실패 시 자동 재시도
  atomic        = false
  cleanup_on_fail = false

  values = [
    yamlencode({
      global = {
        domain = var.argocd_domain != "" ? var.argocd_domain : "argocd.${local.project}.local"
      }

      configs = {
        params = {
          "server.insecure" = true
        }
      }

      server = {
        service = {
          type = "NodePort"
        }

        ingress = {
          enabled = false
        }
      }

      # Redis HA 비활성화 (개발/테스트용)
      redis-ha = {
        enabled = false
      }

      controller = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      repoServer = {
        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd[0],
    module.eks
  ]
}

# ArgoCD Admin Password Secret (초기 비밀번호 설정)
resource "random_password" "argocd_admin" {
  count = var.enable_argocd ? 1 : 0

  length  = 16
  special = true
}

# ArgoCD Application for Backend
# 주의: ArgoCD CRD가 완전히 설치된 후 kubectl로 별도 적용 필요
# resource "kubernetes_manifest" "argocd_app_backend" {
#   count = var.enable_argocd && var.argocd_repo_url != "" ? 1 : 0
# 
#   manifest = {
#     apiVersion = "argoproj.io/v1alpha1"
#     kind       = "Application"
#     metadata = {
#       name      = "${local.project}-backend"
#       namespace = kubernetes_namespace.argocd[0].metadata[0].name
#       finalizers = [
#         "resources-finalizer.argocd.argoproj.io"
#       ]
#     }
#     spec = {
#       project = "default"
# 
#       source = {
#         repoURL        = var.argocd_repo_url
#         targetRevision = var.argocd_repo_branch
#         path           = var.argocd_backend_path
#       }
# 
#       destination = {
#         server    = "https://kubernetes.default.svc"
#         namespace = "default"
#       }
# 
#       syncPolicy = {
#         automated = {
#           prune    = true
#           selfHeal = true
#         }
#         syncOptions = [
#           "CreateNamespace=true"
#         ]
#       }
#     }
#   }
# 
#   depends_on = [
#     helm_release.argocd[0]
#   ]
# }

# ArgoCD Repository Secret (Private Repo용)
resource "kubernetes_secret" "argocd_repo" {
  count = var.enable_argocd && var.argocd_repo_username != "" ? 1 : 0

  metadata {
    name      = "private-repo"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.argocd_repo_url
    username = var.argocd_repo_username
    password = var.argocd_repo_password
  }

  depends_on = [
    helm_release.argocd[0]
  ]
}
