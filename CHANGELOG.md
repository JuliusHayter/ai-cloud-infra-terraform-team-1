# Changelog

## [Unreleased]

### Added

- Séance 4 : énoncé (`docs/seance-4.md`), squelettes `docs/seance-4/` (abonnement BigQuery, SQL des
  compteurs, droits du compte d'exécution, base vectorielle Qdrant), scripts `publish_features.py` et
  `kyc_vectors.py`, modèle de compte rendu, variables `history_topic` et `feature_source`.
- Squelette Terraform de l'équipe (`infra/`) : backend GCS, variables validées, lecture du socle.
- Énoncé de la séance 2 (`docs/seance-2.md`) : Cloud Run à la main, puis Terraform, puis mesures.
- Séance 3 : énoncé (`docs/seance-3.md`), squelette `docs/seance-3/pubsub.tf` (abonnement push, file de
  messages morts), exemple d'enveloppe, modèle de compte rendu, variable `tx_topic`.

### Changed

- L'identifiant d'équipe peut être un nom choisi (`team-really-cool`, `team-ghv`) : `team` suivi de minuscules, chiffres et tirets, 20 caractères au plus.
- Énoncé de la séance 2 : le service lit `customer_daily.parquet` et `terminal_daily.parquet`
  (FraudFinder) au lieu de `history.parquet`.
