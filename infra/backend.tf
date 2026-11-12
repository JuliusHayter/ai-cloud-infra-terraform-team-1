terraform {
  backend "gcs" {
    bucket = "advanced-cloud-ai-tfstate"
    prefix = "team1"
  }
}
