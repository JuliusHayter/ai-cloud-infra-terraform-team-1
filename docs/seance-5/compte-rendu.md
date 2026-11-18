# Compte rendu séance 5 — team1

| Mesure | Valeur |
| --- | --- |
| Étape 0 : lignes relues dans `MANIFEST.json` (`train-sample`, `valid`, `test`) ; version et alias du modèle en place | ... , ... , ... ; version ... , alias ... |
| Étape 1 : `run_id`, commit, image, graine, AP de validation | ... |
| Étape 1 : durée de l'exécution ; `load` et `fit` de `metadata.json` | ... s ; ... s, ... s |
| Étape 3 : `run_id` du modèle 12 mois ; `fit` ; AP de validation | ... ; ... s ; ... |
| Étape 3 : AP test candidat et champion ; écart et IC à 95 % ; verdict | ... , ... ; ... [... ; ...] ; ... |
| Étape 3 : version au registre (ou « refus ») ; `rang_lecture_test` | ... ; ... |
| Étape 4 : débits DDP à 1 et 2 processus ; AP de validation | ... et ... échantillons/s ; ... et ... |
| Lien du dépôt (`infra/job.tf`) | https://github.com/... |

## Recherche (étape 2)

| Étude | Workers | vCPU par tâche | Threads | Essais terminés | `wall_seconds` | Durée de l'exécution | `sum_fit_seconds` | Meilleure AP | Tâches réussies / lancées |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| w1-t1 | 1 | 1 | 1 | ... | ... | ... | ... | ... | ... |
| w4-t1 | 4 | 1 | 1 | ... | ... | ... | ... | ... | ... |
| w8-t1 | 8 | 1 | 1 | ... | ... | ... | ... | ... | ... |
| ... | 4 | ... | ... | ... | ... | ... | ... | ... | ... |

Courbe d'accélération : lien ou image, avec la droite idéale.

Coût de chaque recherche : prix relevés (date), formule, valeurs, hypothèses.

## Threads sur Vertex AI (étape 3, 3 mois)

| Threads | `rows.train` | `load` | `fit` | AP de validation |
| --- | --- | --- | --- | --- |
| 1 | ... | ... s | ... s | ... |
| 4 | ... | ... s | ... s | ... |
| 8 | ... | ... s | ... s | ... |

## Six questions

1. Quelles données, quel code et quelle configuration ont produit notre modèle ?
2. Combien de temps prend la recherche avec un, quatre et huit workers ?
3. Pourquoi le gain n'est-il pas proportionnel au nombre de workers ?
4. Combien a coûté notre recherche, et avec quelles hypothèses ?
5. Le modèle entre-t-il au registre, et sur quelle base ?
6. Démonstration DDP : qu'apporte le second processus, et pourquoi ? Une réponse par étudiant, signée
   de son prénom.
