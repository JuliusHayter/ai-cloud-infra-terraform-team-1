# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "projects/advanced-cloud-ai/locations/europe-west1/services/team1-scorer"
resource "google_cloud_run_v2_service" "scorer" {
  annotations          = {}
  client               = "gcloud"
  client_version       = "544.0.0"
  custom_audiences     = []
  default_uri_disabled = false
  deletion_policy      = "DELETE"
  deletion_protection  = true
  description          = null
  iap_enabled          = false
  ingress              = "INGRESS_TRAFFIC_ALL"
  invoker_iam_disabled = false
  labels               = {}
  launch_stage         = "GA"
  location             = "europe-west1"
  name                 = "team1-scorer"
  project              = "advanced-cloud-ai"
  ssh_enabled          = false
  tags                 = null
  scaling {
    manual_instance_count = 0
    max_instance_count    = 20
    min_instance_count    = 0
    scaling_mode          = null
  }
  template {
    annotations                      = {}
    encryption_key                   = null
    execution_environment            = null
    gpu_zonal_redundancy_disabled    = false
    health_check_disabled            = false
    labels                           = {}
    max_instance_request_concurrency = 4
    revision                         = "team1-scorer-next-1120130222"
    service_account                  = "team1-scorer@advanced-cloud-ai.iam.gserviceaccount.com"
    session_affinity                 = false
    timeout                          = "300s"
    containers {
      args             = []
      base_image_uri   = null
      command          = []
      depends_on       = []
      image            = "europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/ref-fraud-api@sha256:f75174064a724b7cbd0f224f54ff45719e486c39692890cc132c7df12f867506"
      name             = null
      sandbox_launcher = false
      working_dir      = null
      env {
        name  = "BQ_DATASET"
        value = "scoring_next"
      }
      env {
        name  = "DATA_DIR"
        value = "/mnt/models/data"
      }
      env {
        name  = "FEATURE_READER"
        value = "snapshot"
      }
      env {
        name  = "FEATURE_SOURCE"
        value = "bigquery"
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = "advanced-cloud-ai"
      }
      env {
        name  = "MODELS_DIR"
        value = "/mnt/models/runs/team1/models/20261118T192703Z4af774"
      }
      env {
        name  = "MODEL_VERSION"
        value = "2"
      }
      env {
        name  = "PREPARED_AT"
        value = "1119180441"
      }
      env {
        name  = "SNAPSHOT_TTL_S"
        value = "86400"
      }
      env {
        name  = "WEB_CONCURRENCY"
        value = "1"
      }
      env {
        name  = "XGB_NTHREAD"
        value = "1"
      }
      ports {
        container_port = 8000
        name           = "http1"
      }
      resources {
        cpu_idle = false
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        startup_cpu_boost = false
      }
      startup_probe {
        failure_threshold     = 60
        initial_delay_seconds = 0
        period_seconds        = 2
        timeout_seconds       = 1
        http_get {
          path = "/health"
          port = 8000
        }
      }
      volume_mounts {
        mount_path = "/mnt/models"
        name       = "models"
        sub_path   = null
      }
    }
    scaling {
      concurrency_utilization = 0
      cpu_utilization         = 0
      max_instance_count      = 3
      min_instance_count      = 0
    }
    volumes {
      name = "models"
      gcs {
        bucket        = "advanced-cloud-ai-models"
        mount_options = []
        read_only     = true
      }
    }
  }
  traffic {
    percent  = 100
    revision = "team1-scorer-candidate-1119195742"
    tag      = null
    type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
  }
  traffic {
    percent  = 0
    revision = "team1-scorer-prep-1119180441"
    tag      = "champion"
    type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
  }
  traffic {
    percent  = 0
    revision = "team1-scorer-candidate-1119195742"
    tag      = "candidate"
    type     = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION"
  }

  # Le service appartient au socle : Terraform refuse de le détruire.
  lifecycle {
    prevent_destroy = true
  }
}
