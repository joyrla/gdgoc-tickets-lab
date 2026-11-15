output "web_url" {
  value = try(google_cloud_run_v2_service.svc["web"].uri, local.web_url)
}

output "image_registry" {
  value = local.registry
}

# Paste into GitHub: Settings → Secrets and variables → Actions → Variables.
# In the lab, students build the trust by hand, and ./lab env github prints these from it.
output "github_variables" {
  value = merge(
    {
      GCP_PROJECT_ID = var.project_id
      GCP_REGION     = var.region
      GAR_REPOSITORY = "gdgoc-tickets"
      WIF_PROVIDER   = try(google_iam_workload_identity_pool_provider.github[0].name, "${local.pool}/providers/gdgoc-tickets")
      DEPLOYER_SA    = local.sa_email["deployer"]
      # With production_extras, a fixable HIGH or CRITICAL problem in the image stops the deploy (ci.yml)
      PRODUCTION_EXTRAS = tostring(var.production_extras)
    },
    { for sa in google_service_account.terraform : "TERRAFORM_SA" => sa.email },
  )
}

output "web_service_name" {
  value = var.web_service_name
}
