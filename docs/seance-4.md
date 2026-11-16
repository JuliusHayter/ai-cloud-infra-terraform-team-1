# Séance 4 — Donner une mémoire au service de scoring

Deux heures, en équipe. Votre service score chaque transaction puis l'oublie. Or 15 des 20 variables
du modèle sont des compteurs sur le passé (nombre de transactions du client sur 1, 7 et 14 jours,
montant moyen, activité du terminal). Aujourd'hui ces compteurs viennent de deux fichiers parquet
arrêtés au 30 septembre 2026. Vous allez garder le flux dans BigQuery, recalculer les compteurs à
partir de cet historique, puis les faire lire par le service, et mesurer ce que coûte chaque lecture.

Dans tout l'énoncé, remplacez `team1` par votre identifiant d'équipe. Votre dataset BigQuery porte ce
nom avec des `_` à la place des tirets (`team-really-cool` → `team_really_cool`). Votre base
Firestore porte exactement votre identifiant d'équipe.

| Étape | Durée | Résultat |
| --- | --- | --- |
| 0. Repartir | 15 min | une requête sur la table d'amorçage ; votre dépôt à jour |
| A. Historiser | 25 min | les transactions du 1er octobre arrivent dans votre table `tx_history` |
| B. Agréger | 40 min | `customer_daily` et `terminal_daily` recalculées, identiques aux fichiers sur septembre |
| C. Servir | 30 min | le service lit ses compteurs dans trois sources, trois latences comparées |
| D. Chercher, en parallèle | 40 min | les justificatifs KYC dans une base vectorielle, un réglage HNSW choisi sur mesure |
| Compte rendu | 10 min | `docs/seance-4/compte-rendu.md` rempli et poussé |

**La partie D est indépendante des trois autres.** Dès la fin de l'étape 0, une personne de l'équipe
la mène seule, pendant que les autres font A, B et C.

**Seule la partie C a besoin de votre service Cloud Run.** Si votre service n'est pas déployé, une
personne s'en occupe pendant que les autres font A et B (énoncé `docs/seance-3.md`, étape 0).

## Ce que vous saurez faire

| # | Compétence | Preuve attendue |
| --- | --- | --- |
| 1 | Garder un flux dans un entrepôt sans écrire de code | `tx_history` remplie par l'abonnement `team1-tx-history` |
| 2 | Borner le coût d'une requête par la partition | octets traités avec et sans filtre, ligne 2 du compte rendu |
| 3 | Calculer une feature fenêtrée sans doublon ni fuite temporelle | `check.sql` renvoie 0 et 0 ; votre réponse à la question B.2 |
| 4 | Choisir où lire une feature au moment de scorer | trois latences p50 et p99 ; la dernière phrase du compte rendu |
| 5 | Régler un index HNSW pour un objectif de rappel et de latence | deux tableaux rappel@10 et latence ; le réglage retenu et sa justification |

## Ce que le socle vous donne

| Ressource | Nom | Vos droits |
| --- | --- | --- |
| Table d'amorçage | `fraudfinder.tx_seed` : 2 108 615 transactions du 10 au 30 septembre 2026, avec le label `TX_FRAUD` | lecture |
| Compteurs de référence | `fraudfinder.ref_customer_daily`, `fraudfinder.ref_terminal_daily` : le contenu des deux fichiers parquet | lecture |
| Votre dataset | `team1` | propriétaire |
| Votre base Firestore | `team1` | lecture et écriture |
| Image du service | `europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/ref-fraud-api:td4` | lecture |
| Justificatifs KYC | `gs://advanced-cloud-ai-models/data/kyc_embeddings.parquet` : 49 394 documents synthétiques, un par client, avec leur embedding (384 dimensions) | lecture |

Tout est en `europe-west1`. Les requêtes se lancent dans la console (BigQuery → Studio) ou avec
`bq query --use_legacy_sql=false --location europe-west1 '...'`.

## Étape 0 — Repartir (15 min)

1. Committez votre travail en cours, puis sur GitHub cliquez **Sync fork** et lancez `git pull`. Vous
   récupérez cet énoncé, le dossier `docs/seance-4/` et deux variables (`history_topic`,
   `feature_source`).
2. Vérifiez que votre abonnement push ne lit pas `ff-replay` : l'enseignant va y publier 100 000
   messages en quelques minutes. La commande doit afficher `ff-tx`, ou une erreur si vous n'avez plus
   d'abonnement. Sinon, remettez `tx_topic` à sa valeur par défaut et appliquez.

   ```bash
   gcloud pubsub subscriptions describe team1-tx-push --format 'value(topic)'
   ```

3. Lancez votre première requête, et notez les **octets traités** affichés par la console :

   ```sql
   SELECT DATE(TX_TS) AS jour, COUNT(*) AS transactions, SUM(TX_FRAUD) AS fraudes
   FROM `fraudfinder.tx_seed`
   WHERE TX_TS >= TIMESTAMP '2026-09-24'
   GROUP BY jour ORDER BY jour;
   ```

**Point de contrôle :** 7 lignes, du 24 au 30 septembre, environ 100 000 transactions par jour.

**Blocages fréquents :**

- `Access Denied` : vous n'êtes pas connecté avec votre compte de l'école (`gcloud auth list`).
- `Not found: Dataset ... in location US` : ajoutez `--location europe-west1`, ou dans la console
  Plus → Paramètres de requête → Emplacement des données.

## Partie A — Historiser (25 min)

Un abonnement **BigQuery** est un troisième type d'abonnement, après pull et push : Pub/Sub écrit
lui-même chaque message dans une table. Aucun service ne tourne, aucun code n'est déployé.

```text
ff-replay ──► team1-tx-history ──► table team1.tx_history   (partie A)
ff-tx ou ff-replay ──► team1-tx-push ──► team1-fraud-api    (séance 3, inchangé)
```

1. Copiez le squelette (`cp docs/seance-4/bigquery.tf infra/`) et complétez les trois trous :

   | Trou | Ce qu'il faut | Indice |
   | --- | --- | --- |
   | (a) `field` | la colonne de partition | la date de la transaction |
   | (b) `table` | `projet.dataset.table` | `var.project_id`, `local.dataset`, `table_id` de la table |
   | (c) deux booléens | `use_table_schema` et `write_metadata` | tous deux à `true` |

2. `terraform validate`, `terraform plan`, `terraform apply`. **Prévenez l'enseignant** : il publie
   le 1er octobre entier dans `ff-replay` quand toutes les équipes sont abonnées. Un abonnement ne
   reçoit que les messages publiés après sa création.
3. Pendant le rejeu, comptez :

   ```sql
   SELECT COUNT(*) AS lignes, COUNT(DISTINCT TX_ID) AS transactions, COUNT(DISTINCT message_id) AS messages
   FROM `team1.tx_history`
   WHERE TX_TS >= TIMESTAMP '2026-10-01';
   ```

4. Relancez la même requête **sans** la clause `WHERE` et comparez les octets traités.

**Point de contrôle :** à la fin du rejeu, 100 859 transactions distinctes du 1er octobre.

**Questions :**

1. Vous avez plus de lignes que de transactions distinctes. Les doublons ont-ils le même
   `message_id` ? Qu'est-ce que cela dit de leur origine : nouvelle livraison par Pub/Sub, ou
   seconde publication ?
2. Votre service était-il nécessaire pour remplir cette table ? Que se serait-il passé si
   l'historisation avait été une ligne de code dans `/pubsub` et que le service avait été arrêté ?
3. Pourquoi partitionner sur `TX_TS` plutôt que sur `publish_time` ? Regardez la date des
   transactions et celle d'aujourd'hui.

**Blocages fréquents :**

- `Permission denied` à la création de la table : `local.dataset` ne correspond pas à votre dataset.
- L'abonnement est créé mais la table reste vide : le rejeu n'a pas commencé, ou le trou (c) est
  resté vide (Pub/Sub cherche alors une colonne `data`).
- `terraform plan` veut créer votre service ou d'autres ressources inattendues : votre tranche de la
  séance 3 n'est pas appliquée. Appliquez seulement la partie A avec
  `terraform apply -target=google_pubsub_subscription.tx_history`.

## Partie B — Agréger (40 min)

Le service lit aujourd'hui deux tables de compteurs, figées dans des fichiers :

| Table | Une ligne par | Colonnes |
| --- | --- | --- |
| `customer_daily` | client et jour | `customer_id`, `day`, `n` (nombre de transactions), `amount_sum` (somme des montants) |
| `terminal_daily` | terminal et jour | `terminal_id`, `day`, `n`, `n_fraud` (nombre de fraudes) |

Vous les recalculez dans votre dataset, à partir de `fraudfinder.tx_seed` (le passé) **et** de
`team1.tx_history` (votre flux). Les noms et les types des colonnes sont à respecter : le service les
lira en partie C.

1. Ouvrez `docs/seance-4/customer_daily.sql`, remplacez `team1`, complétez les trois trous, lancez.
2. Sur le même modèle, écrivez la requête qui crée `team1.terminal_daily`. Le flux ne porte pas de
   label : dans la réunion, la colonne `TX_FRAUD` vaut `NULL` pour les lignes du flux, et
   `n_fraud` se calcule avec `COUNTIF(TX_FRAUD = 1)`. Gardez vos deux requêtes dans `infra/sql/`.
3. Lancez `docs/seance-4/check.sql` (remplacez `team1`).
4. Regardez le client `7989449428740969` :

   ```sql
   SELECT * FROM `team1.customer_daily`
   WHERE customer_id = '7989449428740969' AND day >= '2026-09-29' ORDER BY day;
   ```

**Point de contrôle :** `check.sql` renvoie 0 et 0 ; le client a une ligne au 2026-10-01 avec `n` = 5
et `amount_sum` = 100,79. Cette ligne n'existe dans aucun fichier : elle vient de votre flux.

**Questions :**

1. Lisez `tx_history` directement dans `tx`, sans passer par `flux`, et relancez la requête du
   point 4. Que devient `n` ?
2. Une transaction du 2 octobre à 9 h ne doit lire que les jours jusqu'au 1er octobre. Où cette
   règle est-elle appliquée : dans votre table, ou au moment de la lecture ? Que se passerait-il si
   le compteur du jour même était lu ?
3. `n_fraud` vaut 0 pour le 1er octobre. Est-ce une erreur ? Le service ne lit le taux de fraude
   d'un terminal que 7 jours après : pourquoi ce délai existe-t-il dans un vrai système ?

**Blocages fréquents :**

- `check.sql` renvoie des milliers de lignes côté client : `amount_sum` n'est pas une somme de
  `TX_AMOUNT`, ou le filtre de date de `tx_seed` a changé.
- `Column ... in UNION ALL has incompatible types` : les deux `SELECT` n'ont pas les mêmes colonnes
  dans le même ordre.
- La ligne du 1er octobre manque : le rejeu n'était pas fini, relancez votre requête
  (`CREATE OR REPLACE TABLE` recalcule tout).

## Partie C — Servir (30 min)

L'image `ref-fraud-api:td4` contient le service de la séance 3 avec une variable de plus,
`FEATURE_SOURCE`, qui choisit où il lit les compteurs d'une transaction :

| `FEATURE_SOURCE` | Lecture | Fraîcheur |
| --- | --- | --- |
| `parquet` | en mémoire, fichiers lus au démarrage | figée au 30 septembre |
| `bigquery` | une requête SQL par transaction sur vos deux tables | celle de vos tables |
| `firestore` | deux documents lus par clé | celle de votre dernière copie |

1. Copiez `docs/seance-4/features.tf` dans `infra/` et complétez `run_member`.
2. Dans le conteneur de votre service (`main.tf`), ajoutez quatre variables d'environnement :

   | Nom | Valeur |
   | --- | --- |
   | `FEATURE_SOURCE` | `var.feature_source` |
   | `GOOGLE_CLOUD_PROJECT` | `var.project_id` |
   | `BQ_DATASET` | `local.dataset` |
   | `FIRESTORE_DATABASE` | `var.team` |

3. Dans `terraform.tfvars` : l'image `ref-fraud-api:td4`, `feature_source = "parquet"` et
   `tx_topic = "projects/advanced-cloud-ai/topics/ff-replay"`. `terraform apply`, puis vérifiez que
   la révision utilise bien la nouvelle image (`"source":"parquet"` doit apparaître) :

   ```bash
   URL=$(gcloud run services describe team1-fraud-api --region europe-west1 --format 'value(status.url)')
   TOKEN=$(gcloud auth print-identity-token)
   curl -s -H "Authorization: Bearer $TOKEN" $URL/health
   ```

   Si `source` manque, forcez l'image :
   `gcloud run deploy team1-fraud-api --region europe-west1 --image europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/ref-fraud-api:td4`.

4. **Prévenez l'enseignant** : il publie le 2 octobre dans `ff-replay`, à débit modéré. Chaque ligne
   `scored` de vos logs porte maintenant `source` et `features_ms`, la durée de lecture des compteurs.
   Après deux minutes de flux, relevez p50 et p99 :

   ```bash
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="team1-fraud-api" AND jsonPayload.message="scored" AND jsonPayload.source="parquet"' \
     --freshness 5m --limit 500 --format 'value(jsonPayload.features_ms)' | sort -n \
     | awk '{v[NR]=$1} END {print NR " mesures, p50 = " v[int(NR*0.5)+1] " ms, p99 = " v[int(NR*0.99)+1] " ms"}'
   ```

5. Scorez la transaction de référence et notez le score :

   ```bash
   curl -s -X POST $URL/predict -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"transactions": [{"TX_ID": "275114cae73280e474ca7ad397c5c429a93121d0", "TX_TS": "2026-10-02 00:00:00", "CUSTOMER_ID": "7989449428740969", "TERMINAL_ID": "93986911", "TX_AMOUNT": 20.31}]}'
   ```

6. `feature_source = "bigquery"`, `terraform apply`. Refaites les points 4 et 5 en remplaçant
   `parquet` par `bigquery` dans le filtre. Regardez aussi les messages non acquittés de
   `team1-tx-push` : le service suit-il encore le débit ?
7. Copiez vos compteurs dans Firestore (environ trois minutes), puis
   `feature_source = "firestore"`, `terraform apply`, et refaites les points 4 et 5 :

   ```bash
   gcloud auth application-default login   # une fois, avec votre compte de l'école
   uv run --with google-cloud-bigquery --with google-cloud-firestore docs/seance-4/publish_features.py \
     --project advanced-cloud-ai --dataset team1 --database team1
   ```

**Point de contrôle :** trois couples p50 et p99, et deux scores pour la même transaction : celui de
`parquet`, et celui de `bigquery` et `firestore`, qui sont égaux entre eux.

**Questions :**

1. Pourquoi le score change-t-il entre `parquet` et les deux autres sources, alors que le modèle est
   le même ? Lequel des deux scores est calculé avec ce que le client a fait la veille ?
2. `parquet` est la lecture la plus rapide. Que perd-on en la gardant, avec plusieurs instances et un
   flux qui continue ?
3. BigQuery contient les bonnes données. Pourquoi ne pas le lire à chaque transaction ? Appuyez-vous
   sur votre p50 : combien de transactions par seconde une instance traite-t-elle avec cette
   lecture, et que se passerait-il au palier de 1 000 messages/s de la séance 3 ?
4. Les documents Firestore datent de votre dernière copie. À quelle fréquence faudrait-il la
   relancer, et qui s'en chargerait dans un vrai système ?

**Pas de service déployé à ce stade ?** Faites les points 1, 2 et 7 quand même, et demandez à une
autre équipe de vous montrer ses trois mesures : votre compte rendu indique alors d'où elles viennent.

**Blocages fréquents :**

- La révision ne démarre pas en `bigquery` ou `firestore`, avec `403` ou `Permission denied` dans
  ses logs : `features.tf` n'est pas appliqué ou `run_member` désigne un autre compte. Le droit met
  une à deux minutes à être pris en compte.
- `Not found: Table ... customer_daily` : la partie B n'est pas finie, ou `BQ_DATASET` est faux.
- Aucune ligne `scored` : votre abonnement push lit encore `ff-tx` ; vérifiez `tx_topic`.
- En `firestore`, le score est celui d'un client sans historique : la copie n'a pas été lancée, ou
  `--database` n'est pas votre équipe.

## Partie D — Chercher dans les justificatifs KYC (40 min, une personne, en parallèle)

Chaque client a déposé un justificatif (facture, quittance, bulletin de paie...). Un fraudeur
réutilise le même document pour plusieurs comptes, en changeant un montant ou un numéro. Une
recherche par mots exacts ne le voit pas ; une recherche par **similarité** le voit : chaque document
est représenté par un vecteur de 384 nombres (son embedding, déjà calculé avec le modèle
`intfloat/multilingual-e5-small`), et deux documents proches ont des vecteurs proches.

Comparer un vecteur aux 49 394 autres est une recherche **exacte**. Un index **HNSW** est un graphe
qui ne visite qu'une partie des vecteurs : plus rapide, mais il peut manquer des voisins. Deux
réglages décident du compromis :

| Réglage | Fixé | Effet |
| --- | --- | --- |
| `m` | à la construction de l'index | nombre de liens par document dans le graphe |
| `ef` | à chaque recherche | nombre de candidats explorés avant de répondre |

Le **rappel@10** est la part des 10 vrais plus proches voisins que l'index retrouve.

1. Copiez `docs/seance-4/vectors.tf` dans `infra/`, complétez les deux trous, puis créez seulement
   ces ressources :

   ```bash
   cd infra
   terraform apply -target=google_cloud_run_v2_service_iam_member.vectors_invokers
   cd ..
   VURL=$(gcloud run services describe team1-vectors --region europe-west1 --format 'value(status.url)')
   export TOKEN=$(gcloud auth print-identity-token)
   RUN="uv run --with httpx --with pyarrow --with numpy docs/seance-4/kyc_vectors.py"
   gcloud storage cp gs://advanced-cloud-ai-models/data/kyc_embeddings.parquet .
   ```

2. Chargez les documents et construisez l'index avec `m = 16` (trois à quatre minutes), puis
   mesurez :

   ```bash
   $RUN load --url $VURL --m 16
   $RUN measure --url $VURL
   ```

   `measure` lance 300 recherches en exact, puis les mêmes avec `ef` de 4 à 256. Le temps affiché
   est celui mesuré par le serveur, sans le réseau. Copiez le tableau dans le compte rendu.
3. Reconstruisez avec `m = 4` et mesurez à nouveau :

   ```bash
   $RUN load --url $VURL --m 4
   $RUN measure --url $VURL
   ```

4. Choisissez le réglage (`m`, `ef`) le moins coûteux qui tient un rappel@10 d'au moins 0,95.
5. Cherchez les voisins du document 87 :

   ```bash
   $RUN neighbours --url $VURL --doc-id 87
   ```

**Point de contrôle :** deux tableaux de mesures, un réglage retenu, et les trois clients qui ont
présenté le même bulletin de paie que le client `0018478647296750`.

**Questions :**

1. Pour `m = 4`, que gagne-t-on et que perd-on en passant `ef` de 4 à 256 ? Et en passant de `m = 4`
   à `m = 16` à `ef` égal ?
2. La recherche exacte prend environ dix millisecondes sur 49 394 documents. À partir de quel volume
   l'index devient-il nécessaire ? Appuyez-vous sur le fait que la recherche exacte lit tous les
   vecteurs.
3. Un rappel de 0,95 signifie qu'un voisin sur vingt est manqué. Est-ce acceptable pour retrouver un
   document réutilisé ? Pour proposer des documents similaires à un analyste ?
4. Qu'avez-vous mis dans `scaling`, et pourquoi ? Que devient l'index si l'instance redémarre ?
5. Si on change de modèle d'embedding, que faut-il recalculer ?

**Blocages fréquents :**

- `HTTP 403` : `TOKEN` a expiré (une heure) ou votre adresse n'est pas dans `invokers`.
- `HTTP 404` sur la collection : `load` n'a pas été lancé, ou l'instance a redémarré et a perdu
  l'index ; relancez `load`.
- `terraform apply -target` propose de créer d'autres ressources que `team1-vectors` et ses droits
  d'appel : refusez et appelez l'enseignant.

## Compte rendu (10 min)

Remplissez `docs/seance-4/compte-rendu.md` dans votre fork, puis commit et push, avec vos deux
requêtes dans `infra/sql/`.

## Fin de séance

Remettez `tx_topic` à sa valeur par défaut ou détruisez votre tranche :

```bash
cd infra
terraform destroy
gcloud pubsub subscriptions list --filter 'name~team1-' --format 'value(name)'
```

La seconde commande ne doit rien renvoyer. Votre dataset et votre base Firestore appartiennent au
socle : ils restent en place.
