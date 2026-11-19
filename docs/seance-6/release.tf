# Séance 6, « Après le TD » : l'abonnement d'ombre et la règle d'alerte de votre équipe.
# À copier dans infra/release.tf. Il utilise var.team, var.project_id et var.region de infra/variables.tf.
# Trois choix à faire dans la règle d'alerte, repérés par "À COMPLÉTER". Avant l'apply,
# grep -n 'À COMPLÉTER' infra/release.tf ne doit rien renvoyer.

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
      # À COMPLÉTER (1) : le signal. Remplacez les trois "À COMPLÉTER" du filtre et de aggregations
      # par les trois valeurs d'une de ces lignes (type de métrique, aligneur, réducteur) :
      #   latence Cloud Run, en ms       : run.googleapis.com/request_latencies               ALIGN_PERCENTILE_95  REDUCE_MAX
      #   messages scorés ou en échec    : logging.googleapis.com/user/td6_scored ou td6_failed  ALIGN_SUM            REDUCE_SUM
      #   distribution des scores        : logging.googleapis.com/user/td6_score              ALIGN_PERCENTILE_50  REDUCE_MAX
      # Pour restreindre le filtre, ajoutez AND metric.label.<libellé>=\"<valeur>\". Libellés de td6_scored :
      # service, revision, decision, shadow, degraded ; de td6_score et td6_failed : service, revision.
      filter = "metric.type=\"À COMPLÉTER\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"${var.team}-scorer\""

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "À COMPLÉTER"
        cross_series_reducer = "À COMPLÉTER"
        group_by_fields      = ["resource.label.revision_name"]
      }

      comparison = "COMPARISON_GT"

      # À COMPLÉTER (2) : le seuil, dans l'unité de la métrique, par révision et par minute :
      # des ms, un nombre de messages ou un score.
      threshold_value = "À COMPLÉTER"

      # À COMPLÉTER (3) : combien de temps le seuil doit être franchi avant que la règle s'ouvre,
      # un multiple de 60 s : "0s", "60s", "300s"...
      duration = "À COMPLÉTER"

      trigger {
        count = 1
      }
    }
  }
}
