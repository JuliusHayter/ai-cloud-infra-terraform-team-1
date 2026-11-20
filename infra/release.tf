# Séance 6, « Après le TD » : l'abonnement d'ombre et la règle d'alerte de votre équipe.
# À copier dans infra/release.tf. Il utilise var.team, var.project_id et var.region de infra/variables.tf.
# Les trois choix de la règle d'alerte (signal, seuil, durée) sont faits et justifiés ci-dessous.

variable "shadow_tag" {
  description = "Tag de la révision qui reçoit l'ombre (candidate, degrade...). Vide : pas d'abonnement d'ombre."
  type        = string
  default     = ""
}

data "google_cloud_run_v2_service" "scorer" {
  name     = "${var.team}-scorer"
  location = var.region
}

locals {
  shadow_url = one([
    for t in data.google_cloud_run_v2_service.scorer.traffic_statuses : t.uri if t.tag == var.shadow_tag
  ])
}

# Mêmes réglages que shadow.sh. L'audience est l'adresse du service, pas celle du tag.
resource "google_pubsub_subscription" "shadow" {
  count = var.shadow_tag == "" ? 0 : 1

  name  = "${var.team}-shadow"
  topic = "projects/${var.project_id}/topics/ff-td6"

  ack_deadline_seconds       = 30
  message_retention_duration = "3600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "60s"
  }

  push_config {
    push_endpoint = "${local.shadow_url}/pubsub/shadow"

    oidc_token {
      service_account_email = "${var.team}-scorer-push@${var.project_id}.iam.gserviceaccount.com"
      audience              = data.google_cloud_run_v2_service.scorer.uri
    }
  }

  lifecycle {
    precondition {
      condition     = local.shadow_url != null
      error_message = "Le tag ${var.shadow_tag} n'existe pas sur ${var.team}-scorer."
    }
  }
}

# Le projet n'a pas de canal de notification : la règle ouvre un incident dans Monitoring → Alertes.
resource "google_monitoring_alert_policy" "release" {
  display_name = "${var.team}-scorer-release"
  combiner     = "OR"

  user_labels = {
    team = var.team
  }

  conditions {
    display_name = "${var.team}-scorer, par révision"

    condition_threshold {
      # (1) Le signal : la médiane des scores par révision (td6_score, ALIGN_PERCENTILE_50, REDUCE_MAX).
      # La panne de la séance (instantané de features vide) ne se voyait que dans les décisions :
      # latence et échecs n'ont pas bougé. Un compteur d'alertes dépend du volume de trafic de la
      # révision ; la médiane du score, non. Lignes proposées par le squelette :
      #   latence Cloud Run, en ms       : run.googleapis.com/request_latencies               ALIGN_PERCENTILE_95  REDUCE_MAX
      #   messages scorés ou en échec    : logging.googleapis.com/user/td6_scored ou td6_failed  ALIGN_SUM            REDUCE_SUM
      #   distribution des scores        : logging.googleapis.com/user/td6_score              ALIGN_PERCENTILE_50  REDUCE_MAX
      # Pour restreindre le filtre, ajoutez AND metric.label.<libellé>=\"<valeur>\". Libellés de td6_scored :
      # service, revision, decision, shadow, degraded ; de td6_score et td6_failed : service, revision.
      filter = "metric.type=\"logging.googleapis.com/user/td6_score\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.team}-scorer\""

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_50"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["resource.label.revision_name"]
      }

      comparison = "COMPARISON_GT"

      # (2) Le seuil : 0,0012, le seuil de décision du service. Une médiane au-dessus veut dire que plus
      # de la moitié des transactions de la révision sont mises en alerte (normalement environ 14 %,
      # médiane vers 0,0002 ; pendant la panne, 100 % et médiane vers 0,08).
      threshold_value = 0.0012

      # (3) La durée : une minute complète au-dessus du seuil, pour ne pas réagir à un point isolé.
      duration = "60s"

      trigger {
        count = 1
      }
    }
  }
}
