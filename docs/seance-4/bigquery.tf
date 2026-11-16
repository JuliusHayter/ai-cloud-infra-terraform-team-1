# Séance 4, partie A : garder chaque transaction du flux dans une table BigQuery.
# À copier dans infra/ au début de la partie A. Ce fichier ne dépend pas de votre service Cloud Run.
# Trois trous à compléter, repérés par "À COMPLÉTER".

locals {
  # Votre dataset BigQuery, créé par le socle : votre identifiant d'équipe, tirets remplacés par _.
  dataset = replace(var.team, "-", "_")
}

# 1. La table d'historique : une ligne par message reçu.
resource "google_bigquery_table" "tx_history" {
  dataset_id          = local.dataset
  table_id            = "tx_history"
  deletion_protection = false

  time_partitioning {
    type = "DAY"
    # À COMPLÉTER (a) : field, la colonne qui découpe la table en une partition par jour.
    # Indice : la date de la transaction, pas celle de sa réception.
  }

  # Les cinq premières colonnes portent le nom exact des champs du message.
  # Les quatre dernières sont remplies par Pub/Sub (write_metadata).
  schema = jsonencode([
    { name = "TX_ID", type = "STRING" },
    { name = "TX_TS", type = "TIMESTAMP" },
    { name = "CUSTOMER_ID", type = "STRING" },
    { name = "TERMINAL_ID", type = "STRING" },
    { name = "TX_AMOUNT", type = "FLOAT" },
    { name = "subscription_name", type = "STRING" },
    { name = "message_id", type = "STRING" },
    { name = "publish_time", type = "TIMESTAMP" },
    { name = "attributes", type = "JSON" },
  ])
}

# 2. L'abonnement BigQuery : Pub/Sub écrit lui-même chaque message dans la table, sans code.
resource "google_pubsub_subscription" "tx_history" {
  name  = "${var.team}-tx-history"
  topic = var.history_topic

  bigquery_config {
    # À COMPLÉTER (b) : table, au format projet.dataset.table.
    # Indice : var.project_id, local.dataset et l'attribut table_id de la table créée en 1.

    # À COMPLÉTER (c) : deux booléens à true.
    #   use_table_schema : chaque champ du message va dans la colonne du même nom ;
    #   write_metadata   : Pub/Sub remplit message_id, publish_time, subscription_name, attributes.
  }
}

output "history_table" {
  value = "${local.dataset}.${google_bigquery_table.tx_history.table_id}"
}
