# Socle commun, géré par l'enseignant : lecture seule.

data "google_artifact_registry_repository" "images" {
  repository_id = "cloud-ai"
  location      = var.region
}

data "google_storage_bucket" "models" {
  name = "${var.project_id}-models"
}

# Tranche de l'équipe. Chaque nom commence par "${var.team}-".

# 1. Compte de service d'exécution : l'identité sous laquelle tourne le conteneur.
resource "google_service_account" "run" {
  account_id   = "${var.team}-run"
  display_name = "${var.team} : exécution Cloud Run fraud-api"
}

# 2. Ses droits, au plus juste.
resource "google_storage_bucket_iam_member" "run_reads_models" {
  bucket = data.google_storage_bucket.models.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.run.member
}

resource "google_project_iam_member" "run_writes_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.run.member
}

# 3. Service Cloud Run, privé.
resource "google_cloud_run_v2_service" "api" {
  name                = "${var.team}-fraud-api"
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.run.email
    execution_environment            = "EXECUTION_ENVIRONMENT_GEN2" # recommandé pour les volumes Cloud Storage
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    volumes {
      name = "models"
      gcs {
        bucket    = data.google_storage_bucket.models.name
        read_only = true
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "DATA_DIR"
        value = "/mnt/models/data"
      }
      env {
        name  = "WEB_CONCURRENCY"
        value = "1"
      }
      env {
        name  = "XGB_NTHREAD"
        value = "1"
      }

      volume_mounts {
        name       = "models"
        mount_path = "/mnt/models"
      }
    }
  }

  # Le conteneur ne doit pas démarrer avant que son compte puisse lire le bucket.
  depends_on = [google_storage_bucket_iam_member.run_reads_models]
}

# 4. Qui peut appeler le service : uniquement les identités listées, jamais allUsers.
resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.invokers)

  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = each.value
}
