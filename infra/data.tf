# Where state lives. Cloud Run instances keep nothing, so everything that must
# survive goes here: registrations in Firestore, files in Cloud Storage,
# secrets in Secret Manager.

resource "google_firestore_database" "main" {
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # The core lab can be removed with `terraform destroy`. With production_extras a
  # stray destroy is refused; cleanup.sh turns this off only after asking.
  delete_protection_state = var.production_extras ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy         = "DELETE"

  # Undo mistakes: read the database as it was at any minute of the last 7 days
  point_in_time_recovery_enablement = var.production_extras ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"

  depends_on = [google_project_service.apis]
}

# A full copy every day, kept for 7 days (restores into a new database)
resource "google_firestore_backup_schedule" "daily" {
  count     = var.production_extras ? 1 : 0
  database  = google_firestore_database.main.name
  retention = "604800s"
  daily_recurrence {}
}

# Personal data has an end date. Each signup writes expire_at (event day +
# retention_days, shared/gcp.py) and Firestore deletes the document after it.
# Sign-in codes and the sent-email records expire the same way.
resource "google_firestore_field" "ttl" {
  for_each   = toset(["registrations", "codes", "emails", "login_codes", "sent_emails"])
  database   = google_firestore_database.main.name
  collection = each.value
  field      = "expire_at"

  ttl_config {}
  index_config {} # no index needed on this field
}

# QR codes and posters. Private: web reads files and serves them itself.
resource "google_storage_bucket" "assets" {
  name                        = "${var.project_id}-assets"
  location                    = var.region
  uniform_bucket_level_access = true

  # QR codes are useless after the event. Age counts from the day the ticket was made,
  # which can be weeks before the event, so this is longer than the attendee data's retention.
  lifecycle_rule {
    condition {
      age            = var.retention_days + 60
      matches_prefix = ["tickets/"]
    }
    action {
      type = "Delete"
    }
  }
  public_access_prevention = "enforced" # web serves files; the bucket itself stays private
  force_destroy            = true
}

# Secrets. Terraform generates them, which also means their values are stored
# in the Terraform state file: keep the state in a private bucket (versions.tf).
resource "random_password" "secret" {
  for_each = toset(["ticket-secret", "session-secret"])
  length   = 32
  special  = false
}

locals {
  secret_values = {
    ticket-secret  = random_password.secret["ticket-secret"].result
    session-secret = random_password.secret["session-secret"].result
  }
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = local.secret_values
  secret_id = each.key
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "secrets" {
  for_each    = local.secret_values
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value
}

# The email provider's key (Resend). Terraform makes the empty secret; a person adds the
# value, so it never appears in code or in the Terraform state:
#   gcloud secrets versions add smtp-password --data-file=-
# then sets mail_enabled = true and applies again.
resource "google_secret_manager_secret" "smtp_password" {
  secret_id = "smtp-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# The address emails come from. Added by a person in the same way, so it is not in the
# code, the Terraform state or the service's settings:
#   printf 'noreply@your-verified-domain' | gcloud secrets versions add mail-from --data-file=-
resource "google_secret_manager_secret" "mail_from" {
  secret_id = "mail-from"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

# The waitlist query: one event's waiting registrations, oldest first
# (shared/gcp.py promote_next, waitlist_position)
resource "google_firestore_index" "waitlist" {
  database   = google_firestore_database.main.name
  collection = "registrations"

  fields {
    field_path = "event_id"
    order      = "ASCENDING"
  }
  fields {
    field_path = "status"
    order      = "ASCENDING"
  }
  fields {
    field_path = "created_at"
    order      = "ASCENDING"
  }
}
