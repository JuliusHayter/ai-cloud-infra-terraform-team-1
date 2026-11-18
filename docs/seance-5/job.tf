# Séance 5 : le job Cloud Run d'entraînement et de recherche, son compte de service et ses droits.
# À copier dans infra/ à l'étape 1. Il utilise data.google_storage_bucket.models de infra/main.tf.
# Trois trous à compléter, repérés par "À COMPLÉTER" : ce sont les réglages que votre équipe choisit.
# Les valeurs elles-mêmes se mettent dans terraform.tfvars, pas dans ce fichier.

variable "train_image" {
  description = "Image d'entraînement, avec son tag."
  type        = string
  default     = "europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/fraud-train:td5"
}

variable "train_module" {
  description = "Module lancé par le job : train.job (un entraînement) ou train.search (recherche Optuna)."
  type        = string
  default     = "train.job"

  validation {
    condition     = contains(["train.job", "train.search"], var.train_module)
    error_message = "train_module vaut train.job ou train.search."
  }
}

variable "search_workers" {
  description = "Nombre de tâches du job, toutes lancées en parallèle : les workers de la recherche."
  type        = number
  default     = 1

  validation {
    condition     = var.search_workers >= 1 && var.search_workers <= 8
    error_message = "search_workers est compris entre 1 et 8."
  }
}

variable "threads" {
  description = "Threads XGBoost par tâche (variable THREADS)."
  type        = number
  default     = 1
}

variable "train_cpu" {
  description = "vCPU par tâche."
  type        = string
  default     = "1"
}

variable "train_memory" {
  description = "Mémoire par tâche (4Gi au plus pour 1 vCPU)."
  type        = string
  default     = "2Gi"
}

variable "trials" {
  description = "Nombre total d'essais de la recherche, partagé entre les workers. Imposé : 40."
  type        = number
  default     = 40
}

variable "study" {
  description = "Nom de l'étude Optuna. Par défaut w<workers>-t<threads>."
  type        = string
  default     = null
}

locals {
  runs     = "/gcs/${data.google_storage_bucket.models.name}/runs/${var.team}"
  study    = coalesce(var.study, "w${var.search_workers}-t${var.threads}")
  train_sa = google_service_account.train.member
}

resource "google_service_account" "train" {
  account_id   = "${var.team}-train"
  display_name = "Exécution des entraînements ${var.team}"
}

# Écrire des logs ; enregistrer un modèle au registre Vertex AI (étape 3).
resource "google_project_iam_member" "train_runtime" {
  for_each = toset(["roles/logging.logWriter", "roles/aiplatform.user"])
  project  = var.project_id
  role     = each.value
  member   = local.train_sa
}

# Lire tout le bucket des modèles (train/, models/), écrire seulement sous runs/<équipe>/.
resource "google_storage_bucket_iam_member" "train_reads_models" {
  bucket = data.google_storage_bucket.models.name
  role   = "roles/storage.objectViewer"
  member = local.train_sa
}

resource "google_storage_managed_folder_iam_member" "train_writes_runs" {
  bucket         = data.google_storage_bucket.models.name
  managed_folder = "runs/${var.team}/"
  role           = "roles/storage.objectUser"
  member         = local.train_sa
}

# gcsfuse ne montre un dossier que s'il contient un objet ; sans lui, mkdir runs/ est refusé.
resource "google_storage_bucket_object" "runs_marker" {
  bucket  = data.google_storage_bucket.models.name
  name    = "runs/${var.team}/.keep"
  content = "runs ${var.team}\n"
}

# L'adresse de votre base Optuna (PostgreSQL du socle), rangée par l'enseignant dans un secret.
resource "google_secret_manager_secret_iam_member" "train_reads_storage" {
  secret_id = "optuna-storage-${var.team}"
  role      = "roles/secretmanager.secretAccessor"
  member    = local.train_sa
}

resource "google_cloud_run_v2_job" "train" {
  name                = "${var.team}-train"
  location            = var.region
  deletion_protection = false

  template {
    # À COMPLÉTER (a) : task_count et parallelism.
    # Indice : un worker de la recherche = une tâche du job, et toutes doivent tourner en même temps.

    template {
      service_account = google_service_account.train.email
      timeout         = "3600s"
      max_retries     = 0

      # La base PostgreSQL n'a qu'une adresse IP privée : sans sortie vers le VPC, la recherche ne
      # la joint pas. Seul le trafic vers les adresses privées passe par le VPC.
      vpc_access {
        egress = "PRIVATE_RANGES_ONLY"

        network_interfaces {
          network    = "default"
          subnetwork = "default"
        }
      }

      containers {
        image = var.train_image
        args  = [var.train_module]

        resources {
          limits = {
            # À COMPLÉTER (b) : cpu et memory, à partir des variables de ce fichier.
          }
        }

        env {
          name  = "DATA"
          value = "/gcs/${data.google_storage_bucket.models.name}/train"
        }

        env {
          name  = "OUT"
          value = var.train_module == "train.search" ? "${local.runs}/search" : "${local.runs}/models"
        }

        env {
          name = "THREADS"
          # À COMPLÉTER (c) : le nombre de threads XGBoost, sous forme de chaîne (tostring).
          value = ""
        }

        env {
          name  = "STUDY"
          value = local.study
        }

        env {
          name  = "TRIALS"
          value = tostring(var.trials)
        }

        env {
          name  = "IMAGE"
          value = var.train_image
        }

        env {
          name = "OPTUNA_STORAGE"

          value_source {
            secret_key_ref {
              secret  = "optuna-storage-${var.team}"
              version = "latest"
            }
          }
        }

        volume_mounts {
          name       = "models"
          mount_path = "/gcs/${data.google_storage_bucket.models.name}"
        }
      }

      volumes {
        name = "models"

        gcs {
          bucket    = data.google_storage_bucket.models.name
          read_only = false
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_iam_member.train_runtime,
    google_storage_bucket_iam_member.train_reads_models,
    google_storage_managed_folder_iam_member.train_writes_runs,
    google_storage_bucket_object.runs_marker,
    google_secret_manager_secret_iam_member.train_reads_storage,
  ]
}

output "train_job" {
  value = google_cloud_run_v2_job.train.name
}

output "train_service_account" {
  value = google_service_account.train.email
}
