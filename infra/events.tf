# The ways work starts without a person clicking:
#   Pub/Sub   web announces "registered"               → ticket-worker /
#   Pub/Sub   anyone asks for an email                 → ticket-worker /mail
#   Eventarc  Firestore reports a changed registration → waitlist-promoter
#   Scheduler every 5 minutes                          → housekeeping (job)

# ---------- Pub/Sub: registrations ----------

resource "google_pubsub_topic" "registrations" {
  name       = "registrations"
  depends_on = [google_project_service.apis]
}

# Messages that failed every retry land here instead of retrying forever, from
# both topics: the source subscription is on each message (shared/gcp.py)
resource "google_pubsub_topic" "dead_letter" {
  name       = "dead-letter"
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_subscription" "dead_letter" {
  name                       = "dead-letter"
  topic                      = google_pubsub_topic.dead_letter.id
  message_retention_duration = "604800s" # keep a week to inspect
  ack_deadline_seconds       = 600       # a replay takes two commands per message (scripts/replay-dead-letters.sh)

  # By default Pub/Sub deletes a subscription after 31 days without activity,
  # and messages published after that are lost with no error
  expiration_policy {
    ttl = ""
  }
}

resource "google_pubsub_subscription" "ticket_worker" {
  name                 = "ticket-worker"
  topic                = google_pubsub_topic.registrations.id
  ack_deadline_seconds = 60

  # By default Pub/Sub deletes a subscription after 31 days without activity,
  # and messages published after that are lost with no error
  expiration_policy {
    ttl = ""
  }

  push_config {
    push_endpoint = google_cloud_run_v2_service.svc["ticket-worker"].uri
    # Pub/Sub signs each push with this identity's token; Cloud Run checks it
    oidc_token {
      service_account_email = google_service_account.sa["pubsub-push"].email
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  depends_on = [google_cloud_run_v2_service_iam_member.pubsub_invokes_worker]
}

# ---------- Pub/Sub: emails ----------
# web, ticket-worker and housekeeping ask for emails here; ticket-worker's /mail
# sends them (shared/mail.py). A slow mail server delays a message, never a signup.

resource "google_pubsub_topic" "emails" {
  name       = "emails"
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_subscription" "mailer" {
  name                 = "mailer"
  topic                = google_pubsub_topic.emails.id
  ack_deadline_seconds = 60

  # By default Pub/Sub deletes a subscription after 31 days without activity,
  # and messages published after that are lost with no error
  expiration_policy {
    ttl = ""
  }

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.svc["ticket-worker"].uri}/mail"
    oidc_token {
      service_account_email = google_service_account.sa["pubsub-push"].email
      audience              = google_cloud_run_v2_service.svc["ticket-worker"].uri # the service, not the path
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  # About 4 hours of retries: a mail provider's outage should delay a ticket email,
  # not lose it. Nothing else sends an email again (scripts/replay-dead-letters.sh does, by hand)
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 50
  }

  depends_on = [google_cloud_run_v2_service_iam_member.pubsub_invokes_worker]
}

# ---------- Eventarc: a registration changed (Firestore) ----------
# Every update of a registrations/ document arrives at waitlist-promoter; it acts
# only when a seat-holding registration became cancelled.

resource "google_eventarc_trigger" "registration_changed" {
  name     = "registration-changed"
  location = var.region # the Firestore database's location

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.firestore.document.v1.updated"
  }
  matching_criteria {
    attribute = "database"
    value     = google_firestore_database.main.name
  }
  matching_criteria {
    attribute = "document"
    value     = "registrations/{registration}"
    operator  = "match-path-pattern"
  }
  event_data_content_type = "application/protobuf" # the only format for Firestore events

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.svc["waitlist-promoter"].name
      region  = var.region
    }
  }

  service_account = google_service_account.sa["eventarc"].email

  # The roles that broke the ARC104 lab when they were missing
  depends_on = [
    google_project_iam_member.eventarc_receiver,
    google_cloud_run_v2_service_iam_member.eventarc_invokes_promoter,
  ]
}

# ---------- Cloud Scheduler: housekeeping every 5 minutes ----------
# One recurring job instead of one Scheduler job per date: with many events
# there is no single opening time or deadline (jobs/housekeeping.py).

resource "google_cloud_scheduler_job" "housekeeping" {
  name      = "housekeeping"
  region    = var.region
  schedule  = "*/5 * * * *"
  time_zone = "Asia/Seoul"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.housekeeping.name}:run"
    oauth_token {
      service_account_email = google_service_account.sa["scheduler"].email
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_runs_housekeeping]
}
