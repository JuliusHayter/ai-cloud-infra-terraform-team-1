# Séance 4, partie D : une base vectorielle (Qdrant) sur Cloud Run, pour les justificatifs KYC.
# À copier dans infra/. Ce fichier ne dépend pas de votre service de scoring.
# Deux trous à compléter, repérés par "À COMPLÉTER".

resource "google_cloud_run_v2_service" "vectors" {
  name                = "${var.team}-vectors"
  location            = var.region
  deletion_protection = false

  template {
    scaling {
      # À COMPLÉTER (a) : min_instance_count et max_instance_count.
      # Indice : l'index vit dans la mémoire d'une instance. Que devient-il si l'instance s'arrête ?
      # Que se passe-t-il si deux instances répondent, chacune avec sa mémoire ?
    }

    containers {
      image = "docker.io/qdrant/qdrant:v1.12.4"

      ports {
        container_port = 6333
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
        cpu_idle = false
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "vectors_invokers" {
  for_each = toset(var.invokers)
  name     = google_cloud_run_v2_service.vectors.name
  location = var.region
  # À COMPLÉTER (b) : role, le droit d'appeler un service Cloud Run privé.
  member = each.value
}

output "vectors_url" {
  value = google_cloud_run_v2_service.vectors.uri
}
