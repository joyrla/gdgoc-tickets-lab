output "web_url" {
  value = google_cloud_run_v2_service.svc["web"].uri
}

output "image_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

# Paste into GitHub: Settings → Secrets and variables → Actions → Variables
output "github_variables" {
  value = merge(
    {
      GCP_PROJECT_ID = var.project_id
      GCP_REGION     = var.region
      GAR_REPOSITORY = google_artifact_registry_repository.images.repository_id
      WIF_PROVIDER   = google_iam_workload_identity_pool_provider.github.name
      DEPLOYER_SA    = google_service_account.sa["deployer"].email
      # With production_extras, a fixable HIGH or CRITICAL problem in the image stops the deploy (ci.yml)
      PRODUCTION_EXTRAS = tostring(var.production_extras)
    },
    { for sa in google_service_account.terraform : "TERRAFORM_SA" => sa.email },
  )
}

output "web_service_name" {
  value = google_cloud_run_v2_service.svc["web"].name
}
