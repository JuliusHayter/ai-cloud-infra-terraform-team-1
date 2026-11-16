# Compte rendu séance 4 — team1

| Mesure | Valeur |
| --- | --- |
| Lignes dans `tx_history`, transactions distinctes, doublons | ... lignes, ... `TX_ID` distincts, ... doublons |
| Octets traités par votre requête de comptage, avec puis sans filtre sur `TX_TS` | ... Mo, ... Mo |
| Résultat de `check.sql` | client : ... ; terminal : ... |
| Client `7989449428740969`, jour 2026-10-01 dans `customer_daily` | `n` = ... , `amount_sum` = ... |
| Lecture des compteurs, source `parquet` (p50, p99) | ... ms, ... ms |
| Lecture des compteurs, source `bigquery` (p50, p99) | ... ms, ... ms |
| Lecture des compteurs, source `firestore` (p50, p99) | ... ms, ... ms |
| Score de la transaction `275114ca...` : `parquet`, `firestore` | ... , ... |
| Partie D : réglage retenu pour un rappel@10 ≥ 0,95 | `m` = ... , `ef` = ... ; rappel ... ; p50 ... ms, p95 ... ms |
| Partie D : clients ayant présenté le même document que `0018478647296750` | ... , ... , ... |
| Lien du dépôt (Terraform et SQL) | https://github.com/... |

Collez ici les deux tableaux de `measure` (`m = 16`, puis `m = 4`).

En deux phrases : quelle source garderiez-vous pour scorer en direct, et pourquoi ?
