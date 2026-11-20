# Post-mortem séance 6 — team1

Un post-mortem sans blâme décrit des mécanismes, pas des personnes : ce que le système a permis, ce
qu'il n'a pas vu, ce qui l'aurait vu plus tôt. Chaque affirmation renvoie à une mesure, un extrait de
log ou une courbe.

Résumé en une phrase : la version suivante changeait le dataset des features
(`BQ_DATASET=scoring_next`), dont l'instantané était vide ; le service l'a chargé sans erreur et a
scoré chaque transaction comme celle d'un client sans historique, mettant 100 % de son trafic en
alerte, ce que seul le taux d'alerte par révision a révélé, 2 min 12 s après le passage à 10 %.

Toutes les heures sont celles de Paris, le 20/11/2026.

## 1. Chronologie

| Heure | Événement | Source |
| --- | --- | --- |
| 13:02:22 | révision `next` (`team1-scorer-next-1120130222`) déployée sans trafic à partir de `candidate`, seule variable changée `BQ_DATASET=scoring_next` ; `/health` : `"status":"ok"`, `"dataset":"advanced-cloud-ai.scoring_next"`, `"snapshot_rows":0`, `"snapshot_error":null` | sortie de `release.sh` |
| 13:03:01 | `next` passe à 10 % (`candidate` à 90 %) | commande `update-traffic --to-tags next=10` |
| 13:05:13 | premier écart visible sur le taux d'alerte de `next` : 100 % sur 113 transactions, contre 11,0 % pour `candidate` ; score moyen 0,098 contre 0,002 | `measure.py`, fenêtre de 2 min |
| 13:05:13 | détection : le taux d'alerte de `next` franchit le seuil de retour arrière (21,4 %) | `mesures.md` |
| 13:06 | cause identifiée : instantané de features vide sur `next` (`snapshot_rows` 0 contre 895 180), scores constants et tous au-dessus du seuil | `/health` des deux tags, logs `scored` |
| 13:08:10 | détection confirmée sur la fenêtre complète : 100 % d'alertes sur 291 transactions, contre 13,8 % sur `candidate` | `measure.py`, fenêtre de 5 min |
| 13:17:25 → 13:18:59 | retour arrière : `candidate` à 100 % (commande de 1 min 34 s) | commande `update-traffic --to-tags candidate=100` |
| 13:22:05 | quatre signaux revenus dans leur bande : `candidate` p95 2,7 ms, 0 % d'erreur, 12,2 % d'alertes, âge 0 s ; `next` 0 livraison | `measure.py`, 3 min après la fin du retour arrière |
| 13:22:27 | tag `next` retiré ; `candidate` seul à 100 % | commande `update-traffic --remove-tags next` |

`next` est restée à 10 % jusqu'à 13:17 pour laisser le temps du diagnostic, comme le prévoit le TD.
En production, le retour arrière aurait suivi la détection (13:05), le diagnostic venant ensuite.

## 2. Signal

- Signal qui a détecté la panne : taux d'alerte de la révision `next` (valeur 100 %, borne de retour
  arrière 21,4 %, référence 15,4 % pour le challenger en ombre, 11,6 % pour l'ancien champion à
  l'étape 0).
- Délai entre le passage à 10 % et la détection : 2,2 min (2 min 12 s), soit la première mesure.
- Signaux qui n'ont pas bougé : latence p95 (3,1 ms contre 2,7 ms pour `candidate`), taux d'erreur
  (0 %), âge du plus ancien message (2 s au plus) ; hors critères, dégradés (0 %) et `/health`
  (`status: ok`).
- Transactions traitées par la révision `next` avant la détection : 113, toutes en alerte ; ce
  qu'elle en aurait traité à 100 % : environ 1 320 sur la même durée (10 messages/s × 132 s), toutes
  en alerte, soit environ 1 150 fausses alertes de plus que la normale.

## 3. Cause

- Ce qui a changé entre la révision `candidate` et la révision `next` : une seule variable
  d'environnement, `BQ_DATASET`, de `scoring` à `scoring_next`. Image, modèle (version 2), seuil
  (0,0012) et toutes les autres variables sont repris de `candidate` par `release.sh`.
- Comment ce changement produit le signal observé : au démarrage, le service charge un instantané des
  compteurs client et terminal depuis `BQ_DATASET`. Celui de `scoring_next` contient 0 ligne. La
  lecture réussit (une table vide n'est pas une erreur), donc ni `snapshot_error`, ni mode dégradé,
  ni hausse de latence. Chaque transaction reçoit les valeurs par défaut d'un client et d'un terminal
  sans historique ; le modèle, entraîné à juger ce profil risqué, donne des scores de 0,076 à 0,16,
  tous au-dessus du seuil de 0,0012 : 100 % d'alertes.
- Observation qui l'établit (extrait de log, courbe) :

```text
/health par adresse de tag, 13:06 :
candidate : dataset advanced-cloud-ai.scoring       reader snapshot  snapshot_rows 895180  snapshot_error None  status ok
next      : dataset advanced-cloud-ai.scoring_next  reader snapshot  snapshot_rows 0       snapshot_error None  status ok

Logs scored, 13:05:28-13:05:31 :
next       13:05:28  score 0.077005    decision True   latency_ms 1.69  features_ms 0.61  degraded False
next       13:05:28  score 0.077005    decision True   latency_ms 4.32  features_ms 1.49  degraded False
next       13:05:30  score 0.16223     decision True   latency_ms 1.64  features_ms 0.59  degraded False
candidate  13:05:31  score 0.00021508  decision False  latency_ms 1.38  features_ms 0.51  degraded False
candidate  13:05:31  score 0.00013145  decision False  latency_ms 1.30  features_ms 0.53  degraded False

measure.py, 13:03:10-13:08:10 :
candidate  n 2680  erreurs 0,0 %  alertes  13,8 %  score moyen 0,008  p95 2,7 ms  dégradés 0,0 %
next       n  291  erreurs 0,0 %  alertes 100,0 %  score moyen 0,103  p95 3,1 ms  dégradés 0,0 %
```

La même valeur de score (0,077005) sur des transactions différentes montre des features constantes.

## 4. Action qui aurait détecté plus tôt

| Action | Ce qu'elle aurait vu | Quand (étape de la livraison) | Délai gagné | Responsable |
| --- | --- | --- | --- | --- |
| Faire échouer le démarrage (ou `/health`) quand l'instantané de features est vide ou nettement plus petit que celui de la révision en service | `snapshot_rows: 0` sur `next` | au déploiement, avant tout trafic (`release.sh` affiche `/health`) | toute la panne : 0 transaction touchée au lieu de 291 | équipe qui maintient le service de scoring |
| Rendre le test de fumée de `release.sh` / `release.yml` bloquant sur `snapshot_rows` et sur un `/predict` de transactions connues (score attendu d'un client avec historique) | instantané vide, score 100 fois trop haut | au déploiement, avant tout trafic | toute la panne | équipe de livraison |
| Passer la nouvelle révision en ombre avant 10 %, comme pour le challenger, même pour un simple changement de configuration | 100 % d'alertes en ombre, sans décision appliquée | avant 10 % | les 113 transactions touchées avant détection | équipe de livraison |
| Règle d'alerte Cloud Monitoring sur le taux de décisions vraies par révision (métrique sur logs `td6_scored`, libellé `decision`), seuil 25 % pendant 1 min | 100 % d'alertes sur `next` | pendant le palier 10 %, sans attendre une mesure manuelle | environ 1 min, et une détection qui ne dépend plus d'une personne qui lance `measure.py` | équipe d'exploitation |
| Contrôle de fraîcheur et de volume des datasets de features avant de les rendre utilisables (`scoring_next` vide aurait été refusé) | 0 ligne dans `scoring_next` | à la publication du dataset, avant la livraison | toute la panne | équipe données |
