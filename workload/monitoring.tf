# Rotated signing key for scrolls-app, generated and stored only in encrypted
# Terraform state (never hardcoded in Git).
resource "random_password" "scrolls_signing_key" {
  length  = 48
  special = false
}

# The cluster's monitoring stack: a Helm chart in charts/kube-monitoring.
# Terraform installs it and upgrades it when the chart changes. Bump `version`
# in the chart's Chart.yaml whenever you change a template.
resource "helm_release" "monitoring" {
  name      = "kube-monitoring"
  chart     = "${path.module}/charts/kube-monitoring"
  namespace = "observability"

  create_namespace = true
  wait             = true
  timeout          = 600

  set = [
    {
      name  = "ingress.domain"
      value = var.ingress_domain
    },
  ]

  set_sensitive = [
    {
      name  = "scrolls.credentials.s3AccessKey"
      value = data.terraform_remote_state.core.outputs.scrolls_s3_access_key
    },
    {
      name  = "scrolls.credentials.s3SecretKey"
      value = data.terraform_remote_state.core.outputs.scrolls_s3_secret_key
    },
    {
      name  = "scrolls.credentials.signingKey"
      value = random_password.scrolls_signing_key.result
    },
  ]
}
