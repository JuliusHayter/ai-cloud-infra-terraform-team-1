# Séance 6, « Après le TD » : décrire le service team1-scorer, qui appartient au socle.
# Dossier à part, avec son propre état local (pas de bloc backend).
# Ici, on ne lance ni terraform apply ni terraform destroy : import et plan seulement.

terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }
}

provider "google" {
  project = "advanced-cloud-ai"
  region  = "europe-west1"

  # Sans cette ligne, le fournisseur ajoute un libellé au service et le plan annonce une modification.
  add_terraform_attribution_label = false
}

import {
  to = google_cloud_run_v2_service.scorer
  id = "projects/advanced-cloud-ai/locations/europe-west1/services/team1-scorer"
}
