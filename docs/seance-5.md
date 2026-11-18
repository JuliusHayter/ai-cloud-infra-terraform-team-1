# Séance 5 — Réentraîner le scorer, chercher en parallèle, décider

Deux heures, en équipe. Le modèle de votre service a été entraîné une fois, sur un portable. Vous
allez le réentraîner comme un **job** reproductible, accélérer la recherche d'hyperparamètres en la
distribuant sur plusieurs workers, chiffrer ce que cela coûte, puis décider, sur une règle écrite à
l'avance, si le nouveau modèle entre au registre. Le code d'entraînement et l'image sont fournis :
vous paramétrez, lancez, mesurez, expliquez et décidez.

Dans tout l'énoncé, remplacez `team1` par votre identifiant d'équipe.

| Étape | Durée | Résultat |
| --- | --- | --- |
| 0. Mise en route | 10 min | les trois jeux de données relus ; la version du modèle en place notée |
| 1. Entraîner comme un job | 25 min | un modèle et ses métadonnées dans `runs/team1/models/` |
| 2. Chercher en parallèle | 35 min | 40 essais à 1, 4 et 8 workers ; un tableau, une courbe d'accélération, un coût |
| 3. Passer en managé et enregistrer | 25 min | un modèle entraîné sur Vertex AI ; une version `challenger` au registre, ou un refus chiffré |
| 4. Distribuer un modèle (démonstration) | 15 min | deux débits notés ; votre réponse à la question de l'étape 4 |
| Restitution et nettoyage | 10 min | une décision présentée ; `docs/seance-5/compte-rendu.md` poussé ; plus aucun job |

**Lancez la recherche à 1 worker dès le début de l'étape 2** : elle dure plus de 20 minutes
(mesuré en team0). Les étapes 1 et 2 utilisent le même job Cloud Run, qu'on reconfigure.

## Ce que vous saurez faire

| # | Compétence | Preuve attendue | Points |
| --- | --- | --- | --- |
| 1 | Produire un entraînement reproductible | `metadata.json` de l'étape 1 : un tiers sait quelles données, quel code et quelle configuration ont servi | 4 |
| 2 | Découper correctement les données | découpage temporel respecté ; le jeu de test lu une seule fois (journal `decisions/`) | 3 |
| 3 | Mesurer et expliquer un passage à l'échelle | trois mesures comparables à 1, 4 et 8 workers ; l'écart au gain linéaire expliqué par des causes identifiées | 5 |
| 4 | Chiffrer le coût d'un entraînement | prix, durée, nombre de machines et d'essais, avec vos hypothèses | 3 |
| 5 | Décider de l'entrée au registre | la règle appliquée telle qu'écrite ; la décision découle des chiffres | 3 |
| 6 | Choisir une stratégie de distribution | réponse **individuelle** : ce que DDP réplique, pourquoi le gain n'est pas linéaire, quand FSDP ou ZeRO s'impose | 2 |

Le score du modèle n'est pas évalué. Une optimisation sans gain, ou un refus d'entrée au registre,
est un résultat recevable si la mesure est valide et la conclusion argumentée.

## Ce que le socle vous donne

| Ressource | Nom | Vos droits |
| --- | --- | --- |
| Image d'entraînement | `europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/fraud-train:td5`, modules `train.job`, `train.search`, `train.gate` | lecture |
| Matrices de features | `gs://advanced-cloud-ai-models/train/` : `MANIFEST.json`, `train-sample.parquet`, `valid.parquet`, `test.parquet`, `train-large/<AAAA-MM>.parquet` | lecture |
| Modèle en place (champion) | `gs://advanced-cloud-ai-models/models/` ; au registre Vertex AI : `fraud-scorer-team1`, version 1, alias `champion` | lecture |
| Votre dossier de résultats | `gs://advanced-cloud-ai-models/runs/team1/` : `models/`, `search/`, `decisions/` | écriture, par le compte `team1-train` |
| Votre base Optuna | une base PostgreSQL à adresse IP privée ; son adresse est dans le secret `optuna-storage-team1` | lecture du secret, par le compte `team1-train` |

Dans les conteneurs (Cloud Run comme Vertex AI), le bucket est monté comme un dossier :
`gs://advanced-cloud-ai-models/...` se lit `/gcs/advanced-cloud-ai-models/...`. Le montage ne sait
pas ajouter à la fin d'un fichier : le code écrit un fichier par événement, n'en changez pas le
principe.

**Le découpage est temporel et imposé :**

| Jeu | Période | Usage |
| --- | --- | --- |
| `train-sample` | juin et juillet 2026, 1 transaction sur 10 | entraînement (étapes 1 et 2) |
| `train-large/<AAAA-MM>` | un fichier par mois, jusqu'à 2026-07 | entraînement final (étape 3) |
| `valid` | août 2026 | choix des hyperparamètres : la métrique optimisée y est calculée |
| `test` | septembre 2026 | **lu uniquement par `train.gate`, une fois**, à l'étape 3 |

Le code refuse tout mois d'entraînement à partir de 2026-08. Vos droits vous permettent de lire
`test.parquet` : ne le faites pas. Chaque lecture par `train.gate` est journalisée.

## Étape 0 — Mise en route (10 min)

1. Committez votre travail en cours, puis sur GitHub cliquez **Sync fork** et lancez `git pull`. Vous
   récupérez cet énoncé et le dossier `docs/seance-5/`.
2. Vérifiez vos accès et relisez les volumes :

   ```bash
   gcloud storage ls gs://advanced-cloud-ai-models/train/
   gcloud storage cat gs://advanced-cloud-ai-models/train/MANIFEST.json
   ```

   `MANIFEST.json` donne, pour chaque fichier, son nombre de lignes et son empreinte `sha256`.
3. Notez la version du modèle en place :

   ```bash
   gcloud ai models list --region europe-west1 --filter 'display_name=fraud-scorer-team1'
   gcloud ai models list-version <MODEL_ID> --region europe-west1
   ```

**Point de contrôle :** `train-sample` 611 548 lignes, `valid` 311 624, `test` 301 545 ;
`fraud-scorer-team1` existe, sa version 1 porte l'alias `champion`.

**Blocages fréquents :**

- `AccessDenied` ou `403` : vous n'êtes pas connecté avec votre compte de l'école (`gcloud auth list`).
- `Listed 0 items` sur le registre : vérifiez `--region europe-west1` et l'orthographe de l'équipe.

## Étape 1 — Entraîner comme un job (25 min)

Un **job** Cloud Run est un conteneur qui démarre, fait son travail et s'arrête : pas de port, pas
de requête, on paie la durée d'exécution. Le même job servira à l'étape 2.

1. Copiez le squelette (`cp docs/seance-5/job.tf infra/`) et complétez les trois trous :

   | Trou | Ce qu'il faut | Indice |
   | --- | --- | --- |
   | (a) `task_count`, `parallelism` | le nombre de tâches, et combien tournent en même temps | `var.search_workers` |
   | (b) `cpu`, `memory` | les limites de chaque tâche | `var.train_cpu`, `var.train_memory` |
   | (c) `THREADS` | les threads XGBoost de chaque tâche | `tostring(var.threads)` |

   Lisez aussi ce que le fichier crée : le compte `team1-train` et ses droits au plus juste, la sortie
   vers le VPC (la base Optuna n'a qu'une adresse privée), le volume du bucket.
2. Ajoutez à `infra/terraform.tfvars`, sans toucher aux variables de la séance 4 :

   ```hcl
   train_module   = "train.job"
   search_workers = 1
   threads        = 1
   train_cpu      = "1"
   train_memory   = "2Gi"
   ```

3. `terraform fmt`, `terraform validate`, `terraform plan`. Le plan doit annoncer
   **8 to add, 0 to change, 0 to destroy**. Puis `terraform apply`.
4. Lancez une exécution et attendez sa fin, puis lisez ce qu'elle a écrit :

   ```bash
   gcloud run jobs execute team1-train --region europe-west1 --wait
   gcloud storage ls gs://advanced-cloud-ai-models/runs/team1/models/
   gcloud storage cat gs://advanced-cloud-ai-models/runs/team1/models/<run_id>/metadata.json
   ```

   Comptez environ une minute et demie par exécution à 1 vCPU (mesuré en team0), dont une vingtaine
   de secondes pour lire les données à travers le montage.

**Point de contrôle :** un dossier `runs/team1/models/<run_id>/` avec `model.ubj`, `features.json` et
`metadata.json`. `metadata.json` contient l'instantané des données (lignes et `sha256` de chaque
fichier lu), le commit du code, l'image, la configuration, la graine (42) et l'AP de validation.

**Questions :**

1. Avec ce seul `metadata.json`, qu'est-ce qu'un tiers peut refaire exactement ? Que lui manque-t-il
   encore pour obtenir le même modèle au bit près ?
2. Relancez la même exécution. Le `run_id` change-t-il ? L'AP de validation ? Pourquoi ?
3. Où le test apparaît-il dans `metadata.json` ? Pourquoi est-ce voulu ?

**Blocages fréquents :**

- Le plan veut modifier ou recréer votre service de la séance 4 : vos variables ne sont pas celles
  de la séance 4 (par exemple `feature_source`). Corrigez `terraform.tfvars` jusqu'à obtenir
  `0 to change, 0 to destroy`. Si votre tranche de la séance 4 a été détruite, appliquez seulement le
  job : `terraform apply -target=google_cloud_run_v2_job.train`.
- `Permission denied: '/gcs/advanced-cloud-ai-models/runs'` après l'entraînement : l'objet
  `runs/team1/.keep` de `job.tf` n'existe pas ; vérifiez qu'il est dans le plan, puis relancez.
- `Error 403 ... secret optuna-storage-team1` à l'apply : appelez l'enseignant, le secret de votre
  équipe manque.

## Étape 2 — Chercher en parallèle (35 min)

`train.search` lance une étude **Optuna** : chaque essai tire des hyperparamètres, entraîne sur
`train-sample`, mesure l'AP (précision moyenne) sur `valid`. Les workers sont les tâches parallèles
d'une même exécution ; ils partagent l'étude dans votre base PostgreSQL et s'arrêtent quand elle
compte 40 essais terminés. L'espace de recherche est imposé, pour que les équipes soient comparables :

| Hyperparamètre | Plage | Échelle |
| --- | --- | --- |
| `n_estimators` | 100 à 400 | entière |
| `max_depth` | 3 à 10 | entière |
| `learning_rate` | 0,02 à 0,3 | logarithmique |
| `subsample` | 0,5 à 1,0 | linéaire |
| `colsample_bytree` | 0,5 à 1,0 | linéaire |
| `min_child_weight` | 1 à 20 | logarithmique |

1. Reconfigurez le job pour la recherche, avec 8 tâches possibles en parallèle, puis `terraform
   apply` (le plan ne modifie que `team1-train`) :

   ```hcl
   train_module   = "train.search"
   search_workers = 8
   threads        = 1
   train_cpu      = "1"
   train_memory   = "2Gi"
   ```

2. Lancez les trois mesures **en même temps**, chacune avec son nombre de tâches et **son propre nom
   d'étude**. Chaque tâche a sa propre instance : les trois mesures restent comparables.

   ```bash
   gcloud run jobs execute team1-train --region europe-west1 --async --tasks 1 --update-env-vars STUDY=w1-t1
   gcloud run jobs execute team1-train --region europe-west1 --async --tasks 4 --update-env-vars STUDY=w4-t1
   gcloud run jobs execute team1-train --region europe-west1 --async --tasks 8 --update-env-vars STUDY=w8-t1
   gcloud run jobs executions list --job team1-train --region europe-west1
   ```

   Ordres de grandeur mesurés en team0 (1 vCPU et 1 thread par tâche) : environ 7 min et demie à
   4 workers, 4 min et demie à 8 workers, plus de 20 min à 1 worker. Chaque exécution coûte en plus
   environ 50 s fixes (démarrage, lecture des données, écriture des résultats).
3. Pendant ce temps, choisissez une quatrième configuration à 4 workers, avec un autre couple
   (vCPU par tâche, threads par tâche) : par exemple 4 vCPU et 4 threads (`train_cpu = "4"`,
   `train_memory = "8Gi"`, `threads = 4`). Appliquez-la quand les exécutions à 4 et 8 workers sont
   finies, puis lancez-la avec `--tasks 4` et un nouveau nom d'étude (`STUDY=w4-t4`).
4. Pour chaque étude, lisez le résumé et la durée de l'exécution :

   ```bash
   gcloud storage ls gs://advanced-cloud-ai-models/runs/team1/search/w4-t1/
   gcloud storage cat gs://advanced-cloud-ai-models/runs/team1/search/w4-t1/summary.json
   gcloud run jobs executions describe <exécution> --region europe-west1 \
     --format 'value(metadata.creationTimestamp,status.completionTime,status.succeededCount,status.failedCount)'
   ```

   Dans `summary.json` : `trials_completed`, `wall_seconds` (du début du premier essai à la fin du
   dernier), `sum_fit_seconds` (somme des durées d'entraînement de tous les essais), `best_value`
   (meilleure AP de validation). Chaque worker écrit aussi son `worker-<i>.json` ; `best.json`
   contient les meilleurs hyperparamètres, il servira à l'étape 3.
5. Faites le tableau (une ligne par configuration) et la courbe d'accélération : accélération =
   durée à 1 worker / durée à n workers, à côté de la droite idéale y = n. Précisez quelle durée vous
   utilisez (`wall_seconds` ou durée de l'exécution) et pourquoi.
6. Calculez le coût de chaque recherche. Un job Cloud Run est facturé au vCPU-seconde et au
   Gio-seconde de chaque tâche, pendant qu'elle tourne. Relevez les prix sur la page de tarifs de
   Cloud Run (région `europe-west1`) et notez la date du relevé. Écrivez la formule, les valeurs et
   vos hypothèses (ce que vous comptez ou non : démarrage, base PostgreSQL partagée, stockage).

**Point de contrôle :** un tableau d'au moins trois lignes (1, 4, 8 workers), une courbe
d'accélération, un coût par recherche avec ses hypothèses.

**Questions :**

1. Pourquoi le gain n'est-il pas proportionnel au nombre de workers ? Appuyez-vous sur vos chiffres :
   la part fixe de chaque exécution, le nombre d'essais par worker, `sum_fit_seconds`.
2. Vous avez demandé 40 essais. Combien en a-t-on terminé à 4 et 8 workers ? D'où viennent les
   essais en plus, et combien peut-il y en avoir au plus ?
3. Votre quatrième configuration : qu'a-t-elle changé à la durée d'un essai, à la durée totale et au
   coût ? Que se passe-t-il si threads × workers dépasse le nombre de vCPU payés ?
4. À coût égal, préférez-vous plus de workers ou plus de vCPU par worker ? Pour ce problème, et
   pour un modèle dix fois plus long à entraîner.
5. La meilleure AP diffère d'une étude à l'autre. Est-ce dû au parallélisme ? Que faudrait-il pour
   le savoir ?

**Pièges :**

- Un nom d'étude par exécution. Relancée sur une étude existante, une exécution trouve 40 essais
  terminés et s'arrête aussitôt (`étude ... existante : 40 essais déjà terminés`).
- `trials_completed` dépasse 40 : chaque worker finit l'essai en cours, d'où au plus workers − 1
  essais en plus. C'est attendu.
- threads × workers comparé aux vCPU : le conteneur peut voir plus de CPU que son quota. Mesurez,
  ne supposez pas.
- À 8 workers, une tâche peut finir en échec sur `OSError: [Errno 116] Stale file handle` : deux
  workers ont écrit `summary.json` au même moment. L'étude est complète ; lisez `summary.json`, et
  notez l'échec dans votre compte rendu.

**Blocages fréquents :**

- Toutes les tâches échouent sur une connexion refusée ou expirée à PostgreSQL : le bloc
  `vpc_access` manque dans votre job.
- `--tasks 8` ne lance que quelques tâches à la fois : `parallelism` vaut moins de 8 ; vérifiez le
  trou (a) et `search_workers`.

## Étape 3 — Passer en managé et enregistrer (25 min)

Vous relancez le meilleur entraînement, sur plus de données, en **custom job Vertex AI** : un service
qui provisionne une machine, lance le conteneur et la rend. Puis vous appliquez la règle d'entrée.

1. Choisissez l'étude dont vous prenez les hyperparamètres et relisez-les :

   ```bash
   gcloud storage cat gs://advanced-cloud-ai-models/runs/team1/search/w8-t1/best.json
   ```

2. Lancez l'entraînement final : 12 mois (2025-08 à 2026-07), sur une `n2-standard-8` (8 vCPU),
   8 threads. Le script affiche l'identifiant du job.

   ```bash
   docs/seance-5/custom-job.sh team1 n2-standard-8 8 2025-08 \
     /gcs/advanced-cloud-ai-models/runs/team1/search/w8-t1/best.json
   gcloud ai custom-jobs list --region europe-west1 --filter 'labels.team=team1'
   gcloud ai custom-jobs stream-logs <id> --region europe-west1
   ```

   Lisez `custom-job.sh` : image, type de machine, compte de service `team1-train`, durée maximale
   (45 minutes), et le même `train.job` qu'à l'étape 1, avec `--train large` et `--params`.
3. Pendant qu'il tourne, mesurez l'effet des threads sur moins de données : trois custom jobs
   sur 3 mois (2026-05 à 2026-07), à 1, 4 et 8 threads :

   ```bash
   for t in 1 4 8; do
     docs/seance-5/custom-job.sh team1 n2-standard-8 $t 2026-05 \
       /gcs/advanced-cloud-ai-models/runs/team1/search/w8-t1/best.json
   done
   ```

   Pour chaque run, relevez dans `metadata.json` : `durations_s` (`load`, `fit`), `rows.train`,
   `config.threads`, `valid.ap`.
4. Appliquez la règle d'entrée **une seule fois**, sur le modèle 12 mois. `train.gate` est lancé par
   votre job Cloud Run, avec **une seule tâche** :

   ```bash
   gcloud run jobs execute team1-train --region europe-west1 --wait --tasks 1 \
     --args=train.gate,--candidate,/gcs/advanced-cloud-ai-models/runs/team1/models/<run_id>,--decisions,/gcs/advanced-cloud-ai-models/runs/team1/decisions,--team,team1
   gcloud storage ls gs://advanced-cloud-ai-models/runs/team1/decisions/
   gcloud storage cat gs://advanced-cloud-ai-models/runs/team1/decisions/<fichier>.json
   ```

**La règle d'entrée**, écrite avant de voir le test :

| Élément | Valeur |
| --- | --- |
| Métrique | précision moyenne (AP) |
| Jeu | test, septembre 2026 |
| Comparaison | candidat contre champion (`gs://advanced-cloud-ai-models/models/`), sur les mêmes transactions |
| Incertitude | bootstrap apparié, 200 rééchantillonnages, intervalle de confiance à 95 % de (AP candidat − AP champion) |
| Accepté si | la borne basse de cet intervalle est **supérieure à 0,003** |

Accepté, `train.gate` enregistre le candidat comme nouvelle version de `fraud-scorer-team1` avec
l'alias `challenger` ; le `champion` ne bouge pas. Refusé, rien n'est enregistré. Dans les deux cas,
un fichier de décision est écrit dans `runs/team1/decisions/`, avec la règle, les AP, l'intervalle,
le verdict et le rang de la lecture du test (`rang_lecture_test`).

**Point de contrôle :** un fichier de décision avec `rang_lecture_test` = 1, et soit une version
`challenger` au registre (`gcloud ai models list-version <MODEL_ID> --region europe-west1`), soit un
refus motivé par l'intervalle.

**Questions :**

1. Le modèle entre-t-il au registre ? Citez l'écart d'AP, son intervalle et la marge.
2. Pourquoi une marge de 0,003 et non de 0 ? Que risque-t-on avec 0, sachant que deux entraînements
   de la même recette avec deux graines différentes n'ont pas exactement la même AP ?
3. Pourquoi la décision ne se prend-elle pas sur la validation, qui a servi à choisir les
   hyperparamètres ?
4. Sur vos trois runs de 3 mois, que rapportent 4 puis 8 threads ? La lecture des données
   change-t-elle ?

**Pièges :**

- `--tasks 1` est obligatoire : sans lui, chaque tâche du job lit le test et écrit sa décision.
- Ne relancez pas la décision. Chaque lecture du test est comptée, refus compris ; une deuxième
  lecture se voit dans le journal (`rang_lecture_test` = 2).
- `--dry-run` n'est pas un essai à blanc : il lit le test et journalise la lecture, il n'enregistre
  seulement pas au registre. Ne l'utilisez pas.
- Un refus est un résultat recevable : ne cherchez pas un autre candidat pour passer la règle.

**Blocages fréquents :**

- Le custom job reste longtemps en attente avant de démarrer : Vertex AI provisionne la machine.
  Passez à la suite, ne relancez pas le job.
- `fichier de paramètres introuvable` dans les logs : le chemin de `best.json` est faux (nom
  d'étude), il commence par `/gcs/`, pas par `gs://`.
- `train.gate` échoue avant la lecture du test (`features du candidat et du champion différentes`,
  `journal non inscriptible`) : rien n'est journalisé, corrigez et relancez. Après la lecture, un
  échec est journalisé avec le statut `échec` : appelez l'enseignant avant de relancer.

## Étape 4 — Distribuer un modèle (15 min, démonstration de l'enseignant)

L'enseignant entraîne un petit réseau de neurones sur les mêmes données, en CPU, avec PyTorch DDP
(*Distributed Data Parallel*), sur un puis deux processus, puis montre FSDP comme un changement de
configuration du même script. Vous ne lancez rien.

1. Notez les deux débits affichés (échantillons par seconde), à 1 et à 2 processus, et l'AP de
   validation de chaque run.
2. Notez les lignes du script qui changent entre 1 et 2 processus.

**Question (individuelle, dans le compte rendu) :** qu'apporte le second processus en DDP, et
pourquoi ? Dites ce que DDP réplique sur chaque processus, pourquoi le débit ne double pas, et dans
quel cas FSDP ou ZeRO s'imposerait à la place de DDP.

## Restitution et compte rendu (10 min)

Chaque équipe présente sa décision en une minute : le modèle entre-t-il au registre, et sur quels
chiffres ? Remplissez `docs/seance-5/compte-rendu.md` dans votre fork, puis commit et push, avec
votre `infra/job.tf`.

## Fin de séance

Vérifiez qu'aucun job ne tourne, puis détruisez le job et son compte de service :

```bash
gcloud run jobs executions list --job team1-train --region europe-west1
gcloud ai custom-jobs list --region europe-west1 --filter 'labels.team=team1 AND state=JOB_STATE_RUNNING'
cd infra
terraform destroy -target=google_service_account.train
gcloud run jobs list --region europe-west1 --filter 'metadata.name~team1-'
```

Les deux premières commandes ne doivent montrer aucune exécution ni aucun job en cours ; la dernière
ne doit rien renvoyer. Le `destroy` ciblé supprime le job, le compte
`team1-train` et ses droits, et rien d'autre : relisez le plan, il ne doit pas toucher votre service
de la séance 4. Vos résultats dans `runs/team1/`, votre base Optuna et le registre restent en
place : la séance 6 déploiera le `challenger`.
