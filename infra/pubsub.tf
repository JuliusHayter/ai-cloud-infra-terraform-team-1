# Séance 3 : brancher le service de scoring sur le flux de transactions.
# À copier dans infra/ au début de l'étape 1.
# Ce fichier suppose que votre service Cloud Run s'appelle google_cloud_run_v2_service.api
# dans main.tf ; s'il porte un autre nom, remplacez "api" partout ci-dessous.
# Trois trous à compléter, repérés par "À COMPLÉTER". Tant que (a) et (b) sont vides,
# terraform validate s'arrête sur "Missing required argument" en pointant la ligne à compléter.

# 1. Identité de la livraison : Pub/Sub présente un jeton signé au nom de ce compte.
resource "google_service_account" "push" {
  account_id   = "${var.team}-push"
  display_name = "Livraison Pub/Sub vers le service de scoring ${var.team}"
}

# 2. Ce compte, et lui seul, a le droit d'appeler votre service privé.
resource "google_cloud_run_v2_service_iam_member" "push_invokes_api" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = google_service_account.push.member
}

# 3. File des messages en échec, et un abonnement pull pour les relire.
resource "google_pubsub_topic" "dead" {
  name = "${var.team}-tx-dead"
}

resource "google_pubsub_subscription" "dead_pull" {
  name  = "${var.team}-tx-dead-pull"
  topic = google_pubsub_topic.dead.id
}

# 4. Abonnement push : Pub/Sub appelle votre service à chaque transaction.
resource "google_pubsub_subscription" "tx" {
  name                       = "${var.team}-tx-push"
  topic                      = var.tx_topic
  ack_deadline_seconds       = 30
  message_retention_duration = "3600s"

  push_config {
    # (a) URL appelée par Pub/Sub à chaque message.
    push_endpoint = "${google_cloud_run_v2_service.api.uri}/pubsub"

    oidc_token {
      # (b) Le jeton présenté au service est signé au nom du compte team1-push.
      service_account_email = google_service_account.push.email
      audience              = google_cloud_run_v2_service.api.uri
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  # (c) Après 5 tentatives en échec, le message part dans le topic team1-tx-dead.
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead.id
    max_delivery_attempts = 5
  }

  labels = {
    team = var.team
  }

  depends_on = [google_cloud_run_v2_service_iam_member.push_invokes_api]
}

output "push_subscription" {
  value = google_pubsub_subscription.tx.name
}

output "dead_letter_subscription" {
  value = google_pubsub_subscription.dead_pull.name
}
