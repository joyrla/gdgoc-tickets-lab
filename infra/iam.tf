# Who may do what. Every grant is as narrow as possible: on one bucket, one
# topic or one service instead of the whole project, wherever Google allows it.

locals {
  sa = { for k, v in google_service_account.sa : k => "serviceAccount:${v.email}" }

  # Google-managed identities that act on our behalf
  pubsub_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  # Which runtime identity may read which secret
  secret_access = {
    "web/ticket-secret"           = { sa = "web", secret = "ticket-secret" }
    "web/session-secret"          = { sa = "web", secret = "session-secret" }
    "ticket-worker/ticket-secret" = { sa = "ticket-worker", secret = "ticket-secret" }
  }
}

# ---------- Firestore: every runtime service reads and writes registrations ----------

resource "google_project_iam_member" "firestore" {
  for_each = toset(["web", "ticket-worker", "waitlist-promoter", "housekeeping"])
  project  = var.project_id
  role     = "roles/datastore.user"
  member   = local.sa[each.value]
}

# ---------- Secrets ----------

resource "google_secret_manager_secret_iam_member" "access" {
  for_each  = local.secret_access
  secret_id = google_secret_manager_secret.secrets[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa[each.value.sa]
}

# Only the service that sends email may read the email provider's key
resource "google_secret_manager_secret_iam_member" "worker_reads_smtp_password" {
  secret_id = google_secret_manager_secret.smtp_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa["ticket-worker"]
}

resource "google_secret_manager_secret_iam_member" "worker_reads_mail_from" {
  secret_id = google_secret_manager_secret.mail_from.id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa["ticket-worker"]
}

# ---------- Buckets ----------

resource "google_storage_bucket_iam_member" "web_uses_assets" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectUser" # serves QR codes, writes posters
  member = local.sa["web"]
}

resource "google_storage_bucket_iam_member" "worker_writes_tickets" {
  bucket = google_storage_bucket.assets.name
  role   = "roles/storage.objectUser" # read, write, overwrite
  member = local.sa["ticket-worker"]
}

# ---------- Pub/Sub ----------

resource "google_pubsub_topic_iam_member" "publishers" {
  for_each = toset(["web", "waitlist-promoter", "housekeeping"]) # a new signup, a promoted signup, a repair
  topic    = google_pubsub_topic.registrations.id
  role     = "roles/pubsub.publisher"
  member   = local.sa[each.value]
}

resource "google_pubsub_topic_iam_member" "email_requesters" {
  for_each = toset(["web", "ticket-worker", "housekeeping"]) # sign-in codes, 신청 완료, reminders
  topic    = google_pubsub_topic.emails.id
  role     = "roles/pubsub.publisher"
  member   = local.sa[each.value]
}

# The admin page peeks at failed messages (and hands them straight back)
resource "google_pubsub_subscription_iam_member" "web_reads_dead_letters" {
  subscription = google_pubsub_subscription.dead_letter.id
  role         = "roles/pubsub.subscriber"
  member       = local.sa["web"]
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_invokes_worker" {
  name     = google_cloud_run_v2_service.svc["ticket-worker"].name
  location = var.region
  role     = "roles/run.invoker"
  member   = local.sa["pubsub-push"]
}

# Pub/Sub itself moves failed messages to the dead-letter topic
resource "google_pubsub_topic_iam_member" "agent_publishes_dead_letters" {
  topic  = google_pubsub_topic.dead_letter.id
  role   = "roles/pubsub.publisher"
  member = local.pubsub_agent
}

resource "google_pubsub_subscription_iam_member" "agent_acks_dead_letters" {
  for_each     = { ticket-worker = google_pubsub_subscription.ticket_worker.id, mailer = google_pubsub_subscription.mailer.id }
  subscription = each.value
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_agent
}

# ---------- Eventarc ----------

resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = local.sa["eventarc"]
}

resource "google_cloud_run_v2_service_iam_member" "eventarc_invokes_promoter" {
  name     = google_cloud_run_v2_service.svc["waitlist-promoter"].name
  location = var.region
  role     = "roles/run.invoker"
  member   = local.sa["eventarc"]
}

# ---------- Scheduler ----------

resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_housekeeping" {
  name     = google_cloud_run_v2_job.housekeeping.name
  location = var.region
  role     = "roles/run.invoker" # includes starting a job execution
  member   = local.sa["scheduler"]
}

# Pre-warm: housekeeping changes web's minimum instances. Cloud Run has no permission
# per field, so this is read and update on this one service.
resource "google_project_iam_custom_role" "web_scaler" {
  role_id     = "webScaler"
  title       = "Change web's scaling"
  description = "Read and update one Cloud Run service, without deploying as its service account"
  permissions = ["run.services.get", "run.services.update"]
}

resource "google_cloud_run_v2_service_iam_member" "housekeeping_updates_web" {
  name     = google_cloud_run_v2_service.svc["web"].name
  location = var.region
  role     = google_project_iam_custom_role.web_scaler.id
  member   = local.sa["housekeeping"]
}

# A deliberate exception to least privilege. Cloud Run asks for actAs on every service
# update, even one that changes only scaling (tested: docs/cold-start.md), and actAs
# also allows deploying as web. It is limited to this one job and this one account.
resource "google_service_account_iam_member" "housekeeping_acts_as_web" {
  service_account_id = google_service_account.sa["web"].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa["housekeeping"]
}

# Renamed grants: tell Terraform they are the same, so it renames them instead of
# creating the new one and then deleting the old one (which is the same grant)
moved {
  from = google_pubsub_topic_iam_member.web_publishes
  to   = google_pubsub_topic_iam_member.publishers["web"]
}

moved {
  from = google_storage_bucket_iam_member.writers_assets["ticket-worker"]
  to   = google_storage_bucket_iam_member.worker_writes_tickets
}

moved {
  from = google_pubsub_subscription_iam_member.agent_acks_dead_letters
  to   = google_pubsub_subscription_iam_member.agent_acks_dead_letters["ticket-worker"]
}
