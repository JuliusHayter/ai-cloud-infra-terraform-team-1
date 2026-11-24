# Rapport séance 2 — team1

Répartition : **à compléter par l'équipe** (une ligne : qui a fait quoi).

Dépôts : <https://github.com/JuliusHayter/ai-cloud-infra-terraform-team-1> (Terraform, `infra/main.tf`,
`infra/outputs.tf`) et <https://github.com/JuliusHayter/team1-td2-fraud-api-albertschool> (service).

## Mesures (partie C)

| Mesure | Valeur | Source |
| --- | --- | --- |
| Latence p50, p99 côté serveur | **2,9 ms, 4,7 ms** (min 2,5 ms, max 4,7 ms) | `httpRequest.latency` des 50 requêtes `/health` dans les journaux de requêtes Cloud Run |
| Latence p50, p99 côté client | 60 ms, 104 ms (min 48 ms, max 104 ms) | `curl -w '%{time_total}'`, réseau et TLS compris |
| Latence de démarrage du conteneur | **9,0 s en moyenne sur 27 démarrages** ; médiane par révision jusqu'à 12,1 s, p99 12,7 s | `run.googleapis.com/container/startup_latencies`, 14 derniers jours |
| Instances pendant la mesure | **1** | `run.googleapis.com/container/instance_count` |
| Instances au pic | **3, le maximum autorisé** (`max_instance_count = 3`), sous la montée en charge de la séance 3 (16/11, de 100 à 1 000 messages/s) | même métrique, `docs/seance-3/compte-rendu.md` |

### Protocole

- Le 24/11/2026 de 23:57:11 à 23:57:15 (heure de Paris), 50 requêtes `GET /health` authentifiées,
  l'une après l'autre, avec la commande de l'énoncé, chronométrées par `curl` :

  ```bash
  URL=$(gcloud run services describe team1-fraud-api --region europe-west1 --format 'value(status.url)')
  TOKEN=$(gcloud auth print-identity-token)
  for i in $(seq 50); do curl -s -o /dev/null -w '%{http_code} %{time_total}\n' -H "Authorization: Bearer $TOKEN" $URL/health; done
  ```

  Résultat : 50 réponses `200`, toutes servies par la révision `team1-fraud-api-00006-hgp`.
- La latence côté serveur est relue dans les journaux de requêtes de ces 50 appels : c'est le temps
  mesuré par la plateforme, sans le réseau entre le poste et Google. L'écart avec la mesure côté
  client (environ 57 ms) est le trajet réseau et l'établissement de la connexion HTTPS.
- Pendant la mesure, le service recevait aussi le flux `ff-tx` de la séance 3 (environ
  0,5 message/s sur `/pubsub`) : il était donc déjà chaud, avec une instance. Les chiffres de
  latence sont ceux d'une instance chaude ; aucun démarrage à froid n'a eu lieu pendant la mesure.
- La latence de démarrage ne peut pas être provoquée tant que le flux maintient une instance : elle
  est lue sur l'historique des 27 démarrages des 14 derniers jours, toutes révisions confondues.
  Elle est longue (environ 9 à 12 s) parce qu'au démarrage chaque instance charge le modèle XGBoost
  et les deux fichiers de compteurs depuis le bucket monté en volume, avant de répondre.

### Configuration mesurée

| Élément | Valeur |
| --- | --- |
| Révision | `team1-fraud-api-00006-hgp` |
| Image | `ref-fraud-api:td4` : depuis la séance 4 (partie C), le service tourne avec l'image fournie par l'enseignant, que l'énoncé de la séance 4 impose pour la variable `FEATURE_SOURCE` |
| Ressources | 1 vCPU, 1 Gio, 0 à 3 instances, concurrence 80 |
| Variables | `FEATURE_SOURCE=parquet`, `DATA_DIR=/mnt/models/data`, `WEB_CONCURRENCY=1`, `XGB_NTHREAD=1` |

L'image n'est donc plus celle de la séance 2 : les latences mesurées sont celles de la même route
`/health`, sur la même configuration de service (1 vCPU, 1 Gio, bucket monté), avec l'image de la
séance 4.

## L'image de l'équipe (compétence 1)

L'image `team1-fraud-api` est dans le registre partagé `cloud-ai` :

```text
$ gcloud artifacts docker images list europe-west1-docker.pkg.dev/advanced-cloud-ai/cloud-ai/team1-fraud-api --include-tags
DIGEST (début)  TAGS          CRÉÉE
0f8615b3d84c                  12/11 10:38
14f638208f0f    12-11-26,v1   10/11 16:18
17a05f1e52bb                  10/11 16:06
3ab3b6e1a346                  10/11 15:44
```

Elle est construite avec `docker build --platform linux/amd64`. Preuve qu'elle tourne sur Cloud Run,
qui n'exécute que des images `linux/amd64` : la révision créée par `terraform apply` avec l'image
`team1-fraud-api@sha256:e04dd384…` (image de la séance 3, avec `/pubsub`) a servi le flux le 15/11,
uniquement des réponses 204 (`docs/seance-3/compte-rendu.md`, étape 2).

## Terraform (compétence 2)

`infra/main.tf` crée le compte d'exécution `team1-run`, ses droits, le service `team1-fraud-api` et
le droit d'appel ; `infra/outputs.tf` donne `service_url` et `service_account_email`. Juste après
l'`apply`, `terraform plan` répondait :

```text
No changes. Your infrastructure matches the configuration.
```

Le `terraform.tfvars` (exclu de git) doit être le même pour tous : avec une autre image ou une autre
liste d'appelants, le plan propose de les rétablir. La valeur en service aujourd'hui est l'image
`ref-fraud-api:td4`.

Quand on change une valeur (la mémoire, par exemple), le plan annonce une seule ressource modifiée
en place, `google_cloud_run_v2_service.api` (`1 to change`), et Cloud Run crée une **nouvelle
révision** à chaque modification du gabarit : le service en est à sa sixième révision
(`team1-fraud-api-00006-hgp`). Les révisions précédentes restent dans l'onglet Révisions, sans
trafic.

## Service privé et moindre privilège (compétence 3)

```text
$ curl -s -o /dev/null -w '%{http_code}\n' $URL/health
403
$ curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(gcloud auth print-identity-token)" $URL/health
200
```

Le 403 est renvoyé par Cloud Run avant que la requête n'atteigne le conteneur. `roles/run.invoker`
sur le service n'est donné qu'à `team1-push` (abonnement de la séance 3) et aux comptes de l'équipe ;
`allUsers` n'apparaît nulle part.

Droits de `team1-run` :

| Rôle | Portée | Ajouté par |
| --- | --- | --- |
| `roles/storage.objectViewer` | bucket `advanced-cloud-ai-models` | `infra/main.tf`, séance 2 |
| `roles/logging.logWriter` | projet | `infra/main.tf`, séance 2 |
| `roles/bigquery.jobUser` | projet | `infra/features.tf`, séance 4, partie C (lecture des compteurs dans BigQuery) |
| `roles/datastore.user` | projet | `infra/features.tf`, séance 4, partie C (lecture des compteurs dans Firestore) |

À la séance 2, `team1-run` ne pouvait que lire le bucket des modèles et écrire des logs. Les deux
derniers rôles ont été ajoutés à la séance 4 parce que le service lit alors ses compteurs dans
BigQuery ou dans Firestore.

## Questions de la partie A

1. **Combien de champs remplis à la main, et un coéquipier saurait-il refaire le même service ?**
   Une douzaine dans la console (image, nom, région, authentification, port, mémoire, CPU, maximum
   d'instances, compte de service, volume, point de montage, trois variables). Sans l'énoncé, un
   coéquipier ne saurait pas les refaire à l'identique : rien n'en garde la trace. Avec Terraform,
   ces valeurs sont dans `infra/main.tf`, versionnées, et `terraform apply` les recrée.
2. **Quel compte de service exécute le code, et à quoi a-t-il accès ?** Dans la console, le compte
   commun `cloudai-runner` ; avec Terraform, le compte propre à l'équipe `team1-run`, qui n'a que
   les droits listés ci-dessus.
