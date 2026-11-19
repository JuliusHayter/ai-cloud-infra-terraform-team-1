# Changelog

## [Unreleased]

### Added

- Séance 6 : énoncé (`docs/seance-6.md` : état de départ, critères, validation et ombre, paliers à 10, 50 et 100 %, panne, retour arrière, restitution, extensions, grille) ; `docs/seance-6/measure.py` (mesure par révision depuis les logs du service) ; modèles `mesures.md`, `post-mortem.md` et `checklist.md` (six lignes de préparation opérationnelle).
- Séance 6 : section « Après le TD » de l'énoncé, qui fait écrire en Terraform l'état atteint à la main : service `team1-scorer` décrit dans un dossier séparé `infra/scorer/` (état local, `import` et `-generate-config-out`, `prevent_destroy`, `plan` seulement, jamais `apply` ni `destroy`) ; abonnement d'ombre (`count` sur `shadow_tag`) et règle d'alerte dans `infra/release.tf`, appliqués avec `-target` ; `plan.txt` et les fichiers Terraform ajoutés au livrable et à la ligne Restorable de la checklist.
- Séance 6 : scripts de livraison `docs/seance-6/` (`release.sh` : révision sans trafic avec tag ; `shadow.sh` : abonnement d'ombre ; `validate.sh` : job de validation ; `promote.sh` : alias `champion` ; `lib.sh`) et workflow `release.yml` (`workflow_dispatch`, authentification WIF). `release.sh`, `shadow.sh`, `validate.sh` et `promote.sh` acceptent `--help` et `DRY_RUN=1` ; `lib.sh` est la bibliothèque qu'ils chargent.
- Séance 6 : squelette `docs/seance-6/release.tf`, à copier dans `infra/release.tf` : abonnement d'ombre complet (`shadow_tag`, adresse du tag lue dans `traffic_statuses`, réglages de `shadow.sh`) et règle d'alerte `google_monitoring_alert_policy.release` dont il reste à choisir le signal, le seuil et la durée.
- Séance 5 : énoncé (`docs/seance-5.md`), squelette `docs/seance-5/job.tf` (job Cloud Run
  d'entraînement et de recherche, compte `<équipe>-train`, sortie VPC vers la base Optuna), script
  `custom-job.sh` (entraînement final en custom job Vertex AI), modèle de compte rendu.
- Séance 4 : énoncé (`docs/seance-4.md`), squelettes `docs/seance-4/` (abonnement BigQuery, SQL des
  compteurs, droits du compte d'exécution, base vectorielle Qdrant), scripts `publish_features.py` et
  `kyc_vectors.py`, modèle de compte rendu, variables `history_topic` et `feature_source`.
- Squelette Terraform de l'équipe (`infra/`) : backend GCS, variables validées, lecture du socle.
- Énoncé de la séance 2 (`docs/seance-2.md`) : Cloud Run à la main, puis Terraform, puis mesures.
- Séance 3 : énoncé (`docs/seance-3.md`), squelette `docs/seance-3/pubsub.tf` (abonnement push, file de
  messages morts), exemple d'enveloppe, modèle de compte rendu, variable `tx_topic`.

### Fixed

- Séance 6 : `tag_info` (`lib.sh`) et `release.yml` lisent la révision et l'adresse du tag sans `--filter` (`gcloud run services describe` le refuse), ce qui débloque `release.sh` et `shadow.sh`.
- Séance 6 : l'énoncé précise l'affichage des alias du registre, la colonne de pourcentage vide d'une révision sans trafic, les 500 au démarrage à froid, la borne d'alertes fixée après l'ombre (avec sa place dans `mesures.md`) et le quota de lecture des logs ; `measure.py` réessaie quand ce quota est dépassé.
- Séance 6 : champs `features_ms` et `error` des logs `scored` (tableau des champs et commande de lecture de l'étape 4) ; le total du service dilue le défaut, la ligne par révision le montre ; la mesure du retour arrière attend la fin de la commande et la relecture de la table du trafic.
- Séance 6, « Après le TD » : `add_terraform_attribution_label = false` dans `infra/scorer/main.tf`, pour un plan d'import sans modification ; `template.revision` comparée à la révision qui sert le trafic ; adresses `creator` et `last_modifier` masquées dans `plan.txt` avant le commit ; ombre et alerte écrites à partir du squelette, test de l'ombre par `-var shadow_tag`, absence de canal de notification ; durée indicative.

### Changed

- L'identifiant d'équipe peut être un nom choisi (`team-really-cool`, `team-ghv`) : `team` suivi de minuscules, chiffres et tirets, 20 caractères au plus.
- Énoncé de la séance 2 : le service lit `customer_daily.parquet` et `terminal_daily.parquet`
  (FraudFinder) au lieu de `history.parquet`.
