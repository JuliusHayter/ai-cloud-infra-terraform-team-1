# Séance 6 — Mettre le challenger en service par paliers, encaisser une panne, revenir en arrière

Deux heures, en équipe. Votre challenger de la séance 5 est au registre ; le champion sert la
production. Vous allez fixer vos critères de décision **avant** de toucher au service, valider le
challenger, le faire tourner en ombre, puis lui donner le trafic par paliers (10 %, 50 %, 100 %) en
mesurant à chaque pas. Ensuite, vous recevez une « version suivante » : vous la livrez à 10 %, vous
repérez ce qui ne va pas, vous en trouvez la cause, puis vous revenez en arrière et vous en tirez une
action. Les scripts sont fournis : vous mesurez, comparez à vos critères et décidez.

Dans tout l'énoncé, remplacez `team1` par votre identifiant d'équipe.

| Horaire | Étape | Durée | Résultat |
| --- | --- | --- | --- |
| 0:00 | 0. État de départ | 10 min | quatre valeurs de référence notées |
| 0:10 | 1. Critères | 10 min | critères chiffrés et horodatés ; commande de retour arrière prête |
| 0:20 | 2. Validation et ombre | 20 min | un verdict argumenté ; une révision à 0 % de trafic qui score en ombre |
| 0:40 | 3. Paliers | 25 min | trois lignes de mesures, trois décisions ; l'alias `champion` déplacé |
| 1:05 | 4. Panne | 30 min | le signal, le délai de détection, la cause étayée |
| 1:35 | 5. Retour arrière et post-mortem | 15 min | signaux revenus dans leur bande ; post-mortem ; checklist |
| 1:50 | Restitution | 10 min | 90 secondes par équipe |

**Le retour arrière de l'étape 5 se fait à 1:35, quel que soit votre avancement.**

## Ce que vous saurez faire

| # | Compétence | Preuve attendue | Critère |
| --- | --- | --- | --- |
| 1 | Fixer la règle avant le résultat | critères de l'étape 1 dans `mesures.md` | chiffrés, horodatés avant le premier déploiement |
| 2 | Valider un candidat | verdict de l'étape 2 | appuyé sur les segments et sur l'ombre, pas sur la seule moyenne |
| 3 | Conduire un déploiement par la mesure | tableau des paliers de l'étape 3 | chaque décision renvoie à un critère écrit |
| 4 | Détecter et diagnostiquer | compte rendu de l'étape 4 | signal identifié, cause étayée par une observation |
| 5 | Revenir en arrière et en tirer une action | post-mortem de l'étape 5 | retour vérifié par la mesure, action concrète, aucune mise en cause personnelle |

Le délai de détection n'est pas noté. Un refus d'avancer, un retour arrière ou une ligne de la
checklist à « non » sont des résultats recevables si la mesure est valide et la décision argumentée.

## Ce que le socle vous donne

L'enseignant a créé ces ressources avant la séance. Vous n'appliquez pas de Terraform pendant le
parcours ; vous y revenez une fois le TD terminé, pour écrire en Terraform ce que vous aurez fait à
la main.

| Ressource | Nom | Ce qu'elle fait |
| --- | --- | --- |
| Service de scoring | `team1-scorer` (Cloud Run, `europe-west1`) | la révision en service porte le tag `champion` et sert le modèle champion |
| Flux de transactions | topic `ff-td6`, abonnement `team1-live-push` | pousse vers `/pubsub` un rejeu de transactions, à 10 messages par seconde, pendant toute la séance |
| Lettre morte | `team1-live-dead-pull` | reçoit les messages que le service a refusés trop de fois |
| Job de validation | `team1-validate` (job Cloud Run) | compare le challenger au champion sur le mois de validation |
| Registre | `fraud-scorer-team1` (Vertex AI) | version d'alias `champion` (en service) et version d'alias `challenger` (séance 5) |
| Tableau de bord | « TD6 team1 » (Cloud Monitoring) | latence, requêtes, décisions et scores par révision ; file de messages |
| Scripts | `docs/seance-6/` | `release.sh`, `shadow.sh`, `validate.sh`, `promote.sh`, `measure.py`, `release.yml` ; le squelette `release.tf` de « Après le TD » |

Vos droits : déployer une révision, modifier la répartition du trafic, créer et supprimer un
abonnement Pub/Sub, lire les logs et les métriques, déplacer un alias du registre, créer une règle
d'alerte.

### Deux mots qui se ressemblent

- Un **tag de révision** (Cloud Run) donne une adresse fixe à une révision du service :
  `https://candidate---team1-scorer-....run.app`. On répartit le trafic par tag :
  `--to-tags candidate=10`. Le tag `champion` est posé sur la révision de départ et ne bouge pas.
- Un **alias** (registre Vertex AI) désigne une version du modèle : `fraud-scorer-team1@challenger`.
  Déplacer l'alias `champion` du registre ne change pas le trafic du service, et inversement.

Une révision a aussi un **nom** (`team1-scorer-candidate-1119104512`, par exemple). `release.sh`
l'affiche ; `measure.py` et les logs travaillent avec ce nom, pas avec le tag.

### Ce que le service écrit dans ses logs

Le service journalise une ligne JSON par message reçu, avec le champ `message` :

| `message` | Quand | Champs utiles |
| --- | --- | --- |
| `scored` | le message est scoré | `tx_id`, `revision`, `model_version`, `score`, `decision`, `latency_ms`, `features_ms`, `degraded`, `shadow`, `error` |
| `failed` | le calcul du score échoue | `tx_id`, `revision`, `model_version`, `shadow`, `status`, `error` |
| `rejected` | le message est illisible ou la transaction invalide | `tx_id`, `revision`, `model_version`, `shadow`, `status`, `error` |

`decision` vaut vrai quand `score` atteint le seuil d'alerte du service, 0,0012 par défaut. Sur le
rejeu, le champion met environ 10 % des transactions en alerte.

`latency_ms` est le temps de traitement du message, `features_ms` le temps de lecture des features,
tous deux en millisecondes. Sur une ligne `scored`, `error` n'apparaît qu'en mode dégradé.

Le service a deux points d'entrée Pub/Sub :

- `/pubsub` applique la décision. Il répond 204 si le message est traité, un code d'erreur sinon :
  Pub/Sub relivre alors le message, puis l'envoie en lettre morte.
- `/pubsub/shadow` calcule et journalise le même score avec `shadow` vrai, sans appliquer la
  décision. Il répond 204 : rien n'est relivré. Au démarrage à froid d'une révision, la plateforme
  peut refuser quelques requêtes avec un 500 (« aborted after waiting too long for an available
  instance ») que Pub/Sub relivre ; ces 500 n'apparaissent pas dans `measure.py`, seulement dans le
  graphique des requêtes du tableau de bord.

### Les scripts

Lancez-les depuis la racine de votre dépôt. Chacun accepte `--help` ; avec `DRY_RUN=1` devant, il
affiche les commandes qui écrivent au lieu de les exécuter. Lisez-les avant de les lancer.

| Script | Usage | Ce qu'il fait |
| --- | --- | --- |
| `release.sh` | `docs/seance-6/release.sh team1 <tag> <alias\|version\|-> [CLÉ=VALEUR...]` | déploie une révision **sans trafic**, avec un tag ; reprend les variables d'une révision de base, applique le modèle et les `CLÉ=VALEUR` demandés ; affiche le nom de la révision, l'adresse du tag et la réponse de `/health` |
| `shadow.sh` | `docs/seance-6/shadow.sh team1 <tag>` ou `docs/seance-6/shadow.sh team1 --off` | crée (ou supprime) l'abonnement `team1-shadow`, qui envoie une copie du flux à `<adresse du tag>/pubsub/shadow` |
| `validate.sh` | `docs/seance-6/validate.sh team1` | exécute le job `team1-validate` (champion contre challenger), attend sa fin et affiche sa ligne `VALIDATION` |
| `promote.sh` | `docs/seance-6/promote.sh team1 <version>` | déplace l'alias `champion` du registre sur `<version>` ; ne touche pas au service |
| `measure.py` | `python3 docs/seance-6/measure.py --service team1-scorer ...` | lit les logs du service et résume chaque révision |

Avec `-` à la place du modèle, `release.sh` garde le modèle de la révision de base, et seules les
`CLÉ=VALEUR` passées changent. La base est la révision qui porte le tag `candidate` si ce tag existe,
sinon celle qui a le plus de trafic.

### Mesurer par révision : `measure.py`

`measure.py` lit les logs `scored`, `failed` et `rejected` des dernières minutes et affiche une ligne
par révision. Il n'a besoin que de Python 3 et de `gcloud` authentifié.

Le projet limite le nombre de lectures de logs par minute, toutes équipes confondues : une seule
personne par équipe lance la mesure, et on ne la relance pas en boucle. En cas d'erreur 429, attendez
une minute avant de relancer.

| Option | Rôle |
| --- | --- |
| `--service team1-scorer` | le service à lire (obligatoire) |
| `--minutes 5` | la fenêtre de lecture, en minutes (défaut : 5) |
| `--shadow` | ne compter que les lignes d'ombre (sans elle : seulement le trafic réel) |
| `--revisions A B` | afficher ces révisions même si elles n'ont aucun log dans la fenêtre |
| `--compare A B` | joindre les décisions de A et de B sur les mêmes transactions (ombre comprise) |
| `--json` | sortie JSON au lieu du tableau |
| `--file logs.jsonl` | lire un fichier de logs au lieu d'appeler `gcloud` |

`A` et `B` sont des **noms de révision**, tels que les affichent `release.sh` et
`gcloud run revisions list`, pas des tags.

| Colonne | Définition |
| --- | --- |
| `n` | livraisons journalisées (un message relivré compte plusieurs fois) |
| `tx distinctes` | transactions scorées distinctes (`tx_id`) |
| `erreurs` | part des livraisons en `failed` ou `rejected` |
| `alertes` | part des transactions distinctes dont la décision est vraie |
| `score moyen` | moyenne des scores |
| `p50 ms`, `p95 ms` | latence de traitement mesurée par le service (`latency_ms`), médiane et 95ᵉ centile |
| `dégradés` | part des messages scorés en mode dégradé |

Exemple, sur un petit fichier fabriqué pour montrer le format (huit transactions, dont une relivrée
après un échec) : les valeurs ne sont pas celles de votre service.

```text
$ python3 docs/seance-6/measure.py --service team1-scorer --file exemple.jsonl \
    --compare team1-scorer-00001-x7k team1-scorer-candidate-1119104512
| révision | n | tx distinctes | erreurs | alertes | score moyen | p50 ms | p95 ms | dégradés |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| team1-scorer-00001-x7k | 9 | 8 | 11,1 % | 25,0 % | 0,010 | 41,0 | 58,5 | 0,0 % |
| team1-scorer-candidate-1119104512 | 0 | - | - | - | - | - | - | - |

Comparaison team1-scorer-00001-x7k → team1-scorer-candidate-1119104512 : 8 transactions communes, désaccord 25,0 %, écart d'alertes 0,0 points
```

Ici, le candidat ne tourne qu'en ombre : sa ligne est vide dans le tableau du trafic réel (relancez
avec `--shadow` pour la voir), mais la comparaison joint bien ses décisions à celles du champion.
`désaccord` est la part des transactions communes où les deux décisions diffèrent ; `écart d'alertes`
est le taux d'alerte de B moins celui de A, en points.

Si `measure.py` affiche « la limite de ... entrées est atteinte », les chiffres de cette fenêtre
sont incomplets : ne les notez pas, relancez la mesure.

## Étape 0 — État de départ (10 min)

**Objectif :** une référence chiffrée avant de toucher au service.

1. Committez votre travail en cours, puis sur GitHub cliquez **Sync fork** et lancez `git pull`. Vous
   récupérez cet énoncé et le dossier `docs/seance-6/`.
2. Vérifiez que le service tourne, sur quelle révision, et ce qu'il annonce :

   ```bash
   gcloud run services describe team1-scorer --region europe-west1 \
     --flatten 'status.traffic[]' \
     --format 'table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'
   URL=$(gcloud run services describe team1-scorer --region europe-west1 --format 'value(status.url)')
   curl -sS -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$URL/health"
   ```

3. Vérifiez dans les logs que cette révision score le rejeu :

   ```bash
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="team1-scorer" AND jsonPayload.message="scored"' \
     --freshness 5m --limit 3 --format json
   python3 docs/seance-6/measure.py --service team1-scorer --minutes 10
   ```

4. Ouvrez le tableau de bord : console Google Cloud, projet `advanced-cloud-ai`, **Monitoring →
   Tableaux de bord → « TD6 team1 »**, fenêtre d'une heure. Il contient six graphiques : « Latence p95
   par révision (ms) », « Requêtes par révision et classe de code », « Transactions scorées par
   révision et décision », « Distribution des scores par révision (moyenne) », « Âge du plus ancien
   message non acquitté (s) », « Messages en lettre morte ».
5. Relevez vos quatre valeurs de référence sur les dix dernières minutes et notez-les dans
   `docs/seance-6/mesures.md` :

   | Signal | Où le lire |
   | --- | --- |
   | latence p95 | `p95 ms` de `measure.py` |
   | taux d'erreur | `erreurs` de `measure.py` |
   | taux d'alerte | `alertes` de `measure.py` |
   | âge du plus ancien message en attente | tableau de bord, « Âge du plus ancien message non acquitté (s) » |

**Ce que vous devez voir :** une seule révision à 100 %, avec le tag `champion` ; `/health` répond
`"status":"ok"` avec `"revision"` égal à ce nom de révision et `"threshold":0.0012` ; des lignes
`scored` de moins de cinq minutes ; dans `measure.py`, une ligne pour cette révision, avec un `n`
d'environ 6 000 livraisons sur 10 minutes.

**Preuve à noter :** le nom de la révision en service et les quatre valeurs, avec l'heure du relevé.

**Si vous voyez...**

- `measure.py` répond « Aucune livraison trouvée » ou le tableau de bord est vide : vérifiez le
  projet (`gcloud config get-value project` doit répondre `advanced-cloud-ai`) et la région
  `europe-west1` dans la console. Si c'est bon, le rejeu est peut-être arrêté : appelez l'enseignant.
- Des chiffres qui ne ressemblent pas à ceux de `measure.py` : vérifiez que le tableau de bord
  ouvert est bien « TD6 team1 », celui de votre équipe.
- `401` ou `403` sur `/health` : vous n'êtes pas connecté avec votre compte de l'école
  (`gcloud auth list`).

## Étape 1 — Critères (10 min)

**Objectif :** fixer la règle de décision avant de connaître le résultat.

1. Choisissez un **objectif de service** : la part des transactions scorées sous un seuil de
   latence (par exemple : « 95 % des transactions scorées en moins de ... ms »).
2. Pour chacun des quatre signaux, écrivez un **seuil d'avancement** (on passe au palier suivant) et
   un **seuil de retour arrière** (on revient immédiatement). Entre les deux, vous prolongez
   l'observation.
3. Fixez la **durée d'observation** de chaque palier. À 10 % du trafic et 10 messages par seconde,
   cinq minutes donnent environ 300 messages à la nouvelle révision : en dessous, le taux d'alerte
   d'une révision repose sur trop peu de transactions. Cinq minutes sont conseillées, six au plus :
   au-delà, les trois paliers ne tiennent pas dans les 25 minutes de l'étape 3.
4. Écrivez la **commande de retour arrière**, prête à coller. Le tag `champion` désigne la révision
   en service notée à l'étape 0 ; la seconde forme la nomme directement :

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags champion=100
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-revisions <révision champion>=100
   ```

5. Notez l'heure : vos critères sont figés à partir de maintenant.

**Grille de repli**, si l'équipe ne s'accorde pas sur ses propres valeurs : on avance tant que les
quatre signaux de la nouvelle révision restent dans ces bornes, on revient en arrière dès que l'un en
sort.

| Signal | Borne |
| --- | --- |
| latence p95 | au plus 1,5 fois la référence |
| taux d'erreur | au plus la référence plus 1 point |
| taux d'alerte | entre la moitié et une fois et demie la référence |
| âge du plus ancien message | moins de 60 secondes |

Un écart d'alertes peut venir d'un modèle qui classe autrement : rapprochez-le du désaccord mesuré à
l'étape 2 avant de conclure à une panne. Pour le taux d'alerte, fixez votre borne APRÈS l'ombre de
l'étape 2, à partir de l'écart d'alertes mesuré en ombre, et notez-la dans `mesures.md` : un écart
conforme à celui de l'ombre n'est pas un motif de retour arrière.

**Ce que vous devez voir :** la section « Critères » de `mesures.md` remplie, avec des chiffres et
une heure antérieure à votre premier déploiement.

**Preuve à noter :** les critères horodatés et la commande de retour arrière.

**Si vous voyez...** un critère sans chiffre (« la latence ne doit pas trop augmenter »), il ne
permet aucune décision : chiffrez-le.

## Étape 2 — Validation et ombre (20 min)

**Objectif :** savoir si le challenger a le droit de recevoir du trafic, sans risque pour la
production.

1. Lancez la validation, puis rendez sa ligne lisible :

   ```bash
   docs/seance-6/validate.sh team1 | tee docs/seance-6/validation.txt
   sed -n 's/^VALIDATION //p' docs/seance-6/validation.txt | python3 -m json.tool --no-ensure-ascii
   ```

   Le job compare `fraud-scorer-team1@challenger` à `fraud-scorer-team1@champion` sur août 2026, au
   seuil annoncé par le service. Pendant qu'il tourne, passez au point 2 dans un second terminal.

   Lisez le résultat dans cet ordre :

   | Champ | Ce qu'il dit |
   | --- | --- |
   | `avertissement` | août 2026 a servi à choisir les hyperparamètres du challenger : les écarts sont optimistes pour lui |
   | `contrat` | `ok` vrai si le challenger attend les mêmes features, dans le même ordre, que le code du service |
   | `latence.ms_pour_1000_lignes` | temps de calcul de chaque modèle pour 1 000 transactions |
   | `global` | AP des deux modèles, `ecart` (challenger − champion) et `ic95`, son intervalle de confiance à 95 % |
   | `segments` | la même chose par tranche de montant et d'activité client ; `concluant` est faux sous 30 fraudes |
   | `segment_le_plus_faible` | le segment concluant où l'écart est le plus défavorable au challenger |
   | `rejeu` | sur août, part des transactions où les deux décisions diffèrent (`desaccord`) et taux d'alerte de chaque modèle, en fractions (0,1 = 10 %) |

   Un écart dont l'intervalle contient 0 ne permet pas de dire lequel des deux modèles est meilleur.

2. Déployez le challenger sans trafic, avec le tag `candidate` :

   ```bash
   docs/seance-6/release.sh team1 candidate challenger
   ```

   Notez le nom de la révision (`Révision : team1-scorer-candidate-...`) et la version du modèle
   (`MODEL_VERSION` dans la liste des variables, `model_version` dans `/health`).
3. Vérifiez que le trafic n'a pas bougé :

   ```bash
   gcloud run services describe team1-scorer --region europe-west1 \
     --flatten 'status.traffic[]' \
     --format 'table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'
   ```

4. Branchez la révision en ombre, puis vérifiez au bout de deux minutes qu'elle reçoit des messages :

   ```bash
   docs/seance-6/shadow.sh team1 candidate
   python3 docs/seance-6/measure.py --service team1-scorer --minutes 2 --shadow
   ```

5. Laissez tourner huit à dix minutes, puis comparez les décisions et les latences :

   ```bash
   python3 docs/seance-6/measure.py --service team1-scorer --minutes 8 \
     --compare <révision champion> <révision candidate>
   python3 docs/seance-6/measure.py --service team1-scorer --minutes 8 --shadow
   ```

6. Rendez un verdict : le challenger a-t-il le droit de recevoir du trafic ?

**Ce que vous devez voir :** une ligne `VALIDATION` avec `"contrat": {"ok": true, ...}` ; après
`release.sh`, une réponse de `/health` dont `"revision"` est la nouvelle révision ; dans la table du
trafic, `candidate` sans pourcentage (colonne vide) et `champion` à 100 % ; avec `--shadow`, une ligne pour la révision
candidate et `n` qui grandit d'une mesure à l'autre.

**Preuve à noter :** le verdict, avec le segment le plus faible, l'écart global et son intervalle,
et trois chiffres de comparaison en ombre : désaccord, écart de taux d'alerte, p95 du candidat face à
celui du champion. Remplissez la ligne « ombre » du tableau de `mesures.md`, puis fixez la borne
d'alertes de l'étape 1 à partir de l'écart d'alertes mesuré.

**Questions :**

1. L'écart global est-il en faveur du challenger ? Son intervalle exclut-il 0 ? Que change
   l'avertissement à votre lecture ?
2. Quels segments ne sont pas concluants ? Pourquoi ne pas fonder un verdict sur eux ?
3. Le désaccord en ombre est-il proche du `desaccord` de la validation ? Donnez deux raisons pour
   lesquelles ils peuvent différer.
4. Que vous apprend l'ombre que la validation ne pouvait pas vous apprendre ?

**Si vous voyez...**

- `fraud-scorer-team1@challenger : version introuvable` : votre équipe n'a pas de version
  `challenger` au registre ; appelez l'enseignant.
- `contrat.ok` faux : le challenger n'attend pas les features du service ; il ne doit pas recevoir de
  trafic. Lisez `contrat.raison` et appelez l'enseignant.
- Aucune ligne d'ombre au bout de deux minutes : vérifiez que l'abonnement pointe sur l'adresse du
  tag suivie de `/pubsub/shadow`, puis regardez le graphique « Requêtes par révision et classe de
  code » pour des requêtes refusées (4xx) sur la révision candidate.

  ```bash
  gcloud pubsub subscriptions describe team1-shadow --format 'value(pushConfig.pushEndpoint)'
  ```

## Étape 3 — Déploiement par paliers (25 min)

**Objectif :** remplacer le champion par le challenger en mesurant à chaque pas.

1. Supprimez l'abonnement d'ombre. S'il reste actif, la révision candidate reçoit chaque message deux
   fois, une en ombre et une en réel.

   ```bash
   docs/seance-6/shadow.sh team1 --off
   gcloud pubsub subscriptions describe team1-shadow
   ```

   La seconde commande doit répondre `NOT_FOUND`.
2. Palier à 10 % : passez le trafic, notez l'heure, attendez la fin de votre durée d'observation,
   puis mesurez les deux révisions.

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=10
   python3 docs/seance-6/measure.py --service team1-scorer --minutes <votre durée d'observation> \
     --revisions <révision champion> <révision candidate>
   ```

   Lisez aussi l'âge du plus ancien message sur le tableau de bord. Remplissez la ligne « 10 % » de
   `mesures.md` et décidez : avancer, prolonger ou revenir en arrière, en citant le critère.
3. Palier à 50 %, même démarche :

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=50
   ```

4. Palier à 100 %, même démarche :

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=100
   ```

5. Une fois le palier à 100 % validé, déplacez l'alias `champion` du registre sur la version du
   challenger, notée à l'étape 2 :

   ```bash
   docs/seance-6/promote.sh team1 <version>
   gcloud ai models list --region europe-west1 --filter 'display_name=fraud-scorer-team1'
   gcloud ai models list-version <MODEL_ID> --region europe-west1 \
     --format 'table(versionId,versionAliases.list())'
   ```

   `<MODEL_ID>` est la valeur de la colonne `MODEL_ID` affichée par `gcloud ai models list`.

6. Mettez à jour votre commande de retour arrière : la révision saine est désormais celle du tag
   `candidate`.

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=100
   ```

**Ce que vous devez voir :** à chaque palier, la table du trafic donne `candidate` au pourcentage
demandé et `champion` au reste ; `measure.py` montre les deux révisions, avec un `n` à peu près
proportionnel à leur part du trafic ; à 100 %, la révision champion n'a plus de livraisons. Après
`promote.sh` : `champion : version ... -> version ...`, et `list-version` montre l'alias `champion`
sur la version du challenger.

**Preuve à noter :** trois lignes de mesures (10 %, 50 %, 100 %), une décision par ligne avec le
critère invoqué, l'alias déplacé.

**Questions :**

1. À 10 %, combien de transactions distinctes la révision candidate a-t-elle scorées ? Est-ce assez
   pour juger son taux d'alerte ?
2. Quel signal était le plus proche de votre seuil de retour arrière ? À quel palier ?
3. Après `promote.sh`, le trafic a-t-il changé ? À quoi sert alors l'alias du registre ?

**Si vous voyez...**

- `measure.py --shadow` affiche encore des lignes récentes après le point 1 : l'abonnement d'ombre
  est toujours actif ; relancez `docs/seance-6/shadow.sh team1 --off`.
- Des courbes qui mélangent les révisions : sur le tableau de bord, lisez chaque courbe par
  révision, pas le total du service.
- Envie de décider avant la fin de la fenêtre : attendez. Une décision prise sur deux minutes à 10 %
  repose sur une centaine de messages.

## Étape 4 — Panne (30 min)

**Objectif :** détecter et diagnostiquer un défaut que personne ne vous a annoncé.

1. Vérifiez que `candidate` est à 100 % (table du trafic de l'étape 3). La version suivante se
   construit à partir de la révision qui porte ce tag.

   Si vous avez refusé le challenger à l'étape 3 et êtes revenus sur `champion`, retirez d'abord le
   tag `candidate` :

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --remove-tags candidate
   ```

   La version suivante part alors de la révision en service. Jusqu'à la fin de la séance, lisez
   `champion` partout où `candidate` est écrit, `mesures.md` et `post-mortem.md` compris : retour
   arrière par `--to-tags champion=100`, mesures sur la révision du tag `champion`, état final
   `champion` à 100 %.
2. L'enseignant vous remet une **fiche de livraison** : une ou plusieurs variables `CLÉ=VALEUR`.
   Déployez cette version sans trafic, avec le tag `next`, en recopiant les variables telles quelles :

   ```bash
   docs/seance-6/release.sh team1 next - CLÉ=VALEUR
   ```

   Notez le nom de la révision `next` et lisez la réponse de `/health`.
3. Passez-la à 10 % et notez l'heure exacte : c'est le début de la panne.

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags next=10
   ```

4. Surveillez les deux révisions, toutes les une à deux minutes, avec vos critères sous les yeux :

   ```bash
   python3 docs/seance-6/measure.py --service team1-scorer --minutes 5 \
     --revisions <révision candidate> <révision next>
   ```

   Gardez le tableau de bord ouvert à côté. Dès qu'un signal de la révision `next` franchit votre
   seuil de retour arrière, notez l'heure : c'est la détection. La détection n'est pas une
   décision : notez le premier franchissement, confirmez-le sur la fenêtre complète.
5. Cherchez la cause. Lisez les logs de la révision `next`, puis ceux de la révision `candidate`, et
   comparez :

   ```bash
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.revision_name="<révision next>"' \
     --freshness 10m --limit 20 \
     --format 'table(timestamp,severity,jsonPayload.message,jsonPayload.score,jsonPayload.decision,jsonPayload.latency_ms,jsonPayload.features_ms,jsonPayload.error)'
   ```

   Dans ce TD, la révision `next` reste à 10 % jusqu'à 1:35 pour vous laisser le temps du
   diagnostic. En production, vous reviendriez en arrière dès la détection, et chercheriez la cause
   ensuite.

**Ce que vous devez voir :** dans la table du trafic, `next` à 10 % et `candidate` à 90 % ; dans
`measure.py`, une ligne par révision, la révision `next` avec environ un dixième des livraisons.

**Preuve à noter :** le signal qui a franchi sa borne (valeur et borne), l'heure du passage à 10 %,
l'heure de détection, le délai en minutes, la cause étayée par un extrait de log ou une courbe.
Remplissez la ligne « panne » de `mesures.md`.

**Questions :**

1. Quel signal est sorti de sa bande en premier ? Lesquels n'ont pas bougé ?
2. Parmi vos quatre signaux, lequel aurait suffi seul à détecter cette panne ? Lequel ne l'aurait
   jamais vue ?
3. Combien de transactions la révision `next` a-t-elle traitées avant votre détection ? Combien en
   aurait-elle traité à 100 % ?

**Si vous voyez...**

- `/health` de la révision `next` répond `"status":"ok"` : il prouve que le conteneur démarre, pas
  que la révision se comporte sous trafic comme la révision saine.
- Un total du service qui bouge peu : à 10 %, le total dilue le défaut de la révision `next`. C'est
  la ligne par révision qui le montre nettement : comparez les quatre signaux **révision par
  révision**.
- Aucune ligne pour la révision `next` dans `measure.py` : vérifiez la table du trafic et le nom de
  révision passé à `--revisions`.

## Étape 5 — Retour arrière et post-mortem (15 min)

**Objectif :** revenir à l'état sain, le prouver, et en tirer une action.

1. À 1:35 au plus tard, ramenez tout le trafic sur la révision saine, celle du tag `candidate` (`champion`
   si vous avez refusé le challenger), et notez l'heure :

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=100
   ```

2. La commande de retour arrière peut durer de quelques secondes à plus de deux minutes. Pendant ce
   temps, une partie du trafic suit encore l'ancienne répartition. Attendez la **fin** de la
   commande et relisez la table du trafic. Attendez ensuite trois minutes, puis mesurez sur les
   trois dernières minutes : une mesure lancée plus tôt contiendrait encore la panne. Les quatre
   signaux doivent être revenus dans leur bande. Cloud Run ne revalide rien lors d'un retour
   arrière : seule votre mesure le prouve.

   ```bash
   gcloud run services describe team1-scorer --region europe-west1 \
     --flatten 'status.traffic[]' \
     --format 'table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'
   python3 docs/seance-6/measure.py --service team1-scorer --minutes 3 \
     --revisions <révision candidate> <révision next>
   ```

3. Retirez le tag `next`, puis relisez la table du trafic :

   ```bash
   gcloud run services update-traffic team1-scorer --region europe-west1 --remove-tags next
   gcloud run services describe team1-scorer --region europe-west1 \
     --flatten 'status.traffic[]' \
     --format 'table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'
   ```

4. Rédigez `docs/seance-6/post-mortem.md` : chronologie, signal, cause, action qui aurait détecté
   plus tôt.
5. Remplissez `docs/seance-6/checklist.md`.

**Ce que vous devez voir :** `candidate` (ou `champion` si vous avez refusé le challenger) à 100 %, plus de tag `next` ; dans `measure.py`, la révision
`next` sans livraison sur les dernières minutes et la révision candidate dans vos bornes.

**Preuve à noter :** les quatre signaux après retour (ligne « retour » de `mesures.md`), le
post-mortem en quatre rubriques, la checklist remplie.

**Si vous voyez...**

- La révision du tag `champion` reprendre le trafic alors que vous aviez adopté le challenger : vous
  êtes revenus sur l'ancien modèle. La révision saine, depuis l'étape 3, est celle du tag `candidate`.
  Si vous aviez refusé le challenger, c'est bien `champion` qui est la révision saine.
- Un post-mortem qui désigne une personne : réécrivez-le en termes de mécanisme (« la livraison n'a
  pas été testée sur... », « aucune alerte ne surveillait... »).

## Restitution (10 min)

Chaque équipe présente en 90 secondes :

- ce que contenait votre version suivante, en une phrase ;
- le premier signal qui l'a trahie ;
- le délai entre le passage à 10 % et la détection ;
- l'alerte que vous ajouteriez pour la détecter plus tôt.

## Autre voie : livrer par GitHub Actions

`docs/seance-6/release.yml` fait la même chose que `release.sh`, depuis le dépôt applicatif de votre
équipe (le dépôt du service de scoring, celui de `app.py`, séances 2 et 3), authentifié auprès du projet par fédération d'identité (compte `team1-cd`). Le parcours
principal passe par les scripts ; cette voie sert à l'extension « Livraison ».

1. Copiez le fichier dans `.github/workflows/release.yml` de votre dépôt applicatif, remplacez
   `TEAM: team1` par votre identifiant, poussez sur la branche par défaut.
2. Lancez-le et suivez-le :

   ```bash
   gh workflow run release.yml -f tag=candidate -f model=challenger
   gh run list --workflow release.yml
   gh run watch <run-id>
   ```

Deux différences avec `release.sh` : avec `-` comme modèle, le workflow part de la révision qui a le
plus de trafic ; le test de fumée (`/health` sur l'adresse du tag) n'est pas bloquant
(`continue-on-error: true`).

## Extensions pour les équipes en avance

À commencer une fois l'étape 5 terminée.

| Extension | Ce que vous faites | Preuve attendue |
| --- | --- | --- |
| Dérive | Comparez dans BigQuery trois grandeurs de `fraudfinder.tx_seed` entre la semaine du 10 au 16 septembre et celle du 24 au 30 septembre, avec la requête ci-dessous. | Un tableau d'écarts (valeur de chaque semaine, écart relatif) et une décision : réentraîner ou non. |
| Politique de réentraînement | Choisissez entre un réentraînement au calendrier, sur dérive ou sur résultats. | Cinq lignes de justification, appuyées sur le délai d'arrivée des labels de fraude. |
| Mode dégradé | Demandez à l'enseignant la variable qui fait échouer la lecture des features. Déployez avec elle une révision `degrade` (`release.sh team1 degrade - <variable> DEGRADED_POLICY=allow`), branchez-la en ombre (`shadow.sh team1 degrade`), lisez `dégradés` et `alertes` avec `--shadow` ; recommencez avec `DEGRADED_POLICY=block`. Terminez par `shadow.sh team1 --off` et `--remove-tags degrade`. | Le choix entre laisser passer (`allow`) et bloquer (`block`) quand la lecture des features échoue, avec son coût de chaque côté. |
| Alerte | Dans **Monitoring → Alertes**, créez la règle qui aurait détecté votre panne, nommée `team1-...`, limitée à `team1-scorer`. Métriques disponibles : celles de Cloud Run (`run.googleapis.com/request_latencies`, `request_count`) et les métriques sur logs `td6_scored` (libellés `service`, `revision`, `decision`, `shadow`, `degraded`), `td6_score` et `td6_failed` (libellés `service`, `revision`). | La règle (capture ou JSON), et le délai qu'elle aurait fait gagner par rapport à votre détection. |
| Livraison | Dans votre copie de `release.yml`, rendez le test de fumée bloquant, puis faites-le échouer volontairement. | Une exécution du workflow en échec sur le test de fumée. |

### Requête de l'extension « Dérive »

Trois grandeurs, par semaine : le montant (`TX_AMOUNT`, médiane et 95ᵉ centile), l'activité des
clients (transactions par client actif et par jour, calculée depuis `CUSTOMER_ID` et `TX_TS`) et le
taux de fraude (`TX_FRAUD`). Lancez-la dans la console BigQuery, emplacement `europe-west1`.

```sql
WITH tx AS (
  SELECT
    IF(TX_TS < TIMESTAMP '2026-09-17', '10-16 sept', '24-30 sept') AS semaine,
    CUSTOMER_ID, DATE(TX_TS) AS jour, TX_AMOUNT, TX_FRAUD
  FROM `fraudfinder.tx_seed`
  WHERE (TX_TS >= TIMESTAMP '2026-09-10' AND TX_TS < TIMESTAMP '2026-09-17')
     OR (TX_TS >= TIMESTAMP '2026-09-24' AND TX_TS < TIMESTAMP '2026-10-01')
),
montants AS (
  SELECT semaine,
    APPROX_QUANTILES(TX_AMOUNT, 100)[OFFSET(50)] AS montant_median,
    APPROX_QUANTILES(TX_AMOUNT, 100)[OFFSET(95)] AS montant_p95,
    AVG(TX_FRAUD) AS taux_fraude
  FROM tx
  GROUP BY semaine
),
activite AS (
  SELECT semaine, AVG(n) AS tx_par_client_jour
  FROM (SELECT semaine, CUSTOMER_ID, jour, COUNT(*) AS n FROM tx GROUP BY semaine, CUSTOMER_ID, jour)
  GROUP BY semaine
)
SELECT * FROM montants JOIN activite USING (semaine) ORDER BY semaine;
```

Le taux de fraude de la semaine la plus récente repose sur des labels qui arrivent avec retard :
dites-le dans votre décision.

## Après le TD — Mettre en Terraform ce que vous avez fait à la main

Une fois l'étape 5 terminée, l'état de votre service ne tient qu'à des commandes tapées dans un
terminal. Écrivez-le en Terraform, pour qu'il soit relu, versionné et reconstructible. Comptez
environ une heure.

| Ce que vous avez fait à la main | Fichier | Ressource Terraform | Ce que vous en faites |
| --- | --- | --- | --- |
| Répartition du trafic, tags, modèle et variables de la révision en service | `infra/scorer/scorer.tf` | `google_cloud_run_v2_service.scorer` (`team1-scorer`) | `import` et `terraform plan` seulement, jamais `apply` |
| Abonnement d'ombre `team1-shadow` | `infra/release.tf` | `google_pubsub_subscription.shadow` | `terraform apply`, ombre désactivée |
| Règle d'alerte qui aurait détecté votre panne | `infra/release.tf` | `google_monitoring_alert_policy.release` | `terraform apply` |

1. **Le service, dans un dossier à part.** `team1-scorer` appartient au socle : vous le décrivez,
   vous ne l'appliquez pas. Il ne va pas dans `infra/` : un `terraform apply` sans `-target`
   l'importerait dans l'état de votre équipe et lui imposerait votre configuration, et un
   `terraform destroy` le supprimerait. Créez `infra/scorer/main.tf`. Ce dossier a son propre état,
   local : pas de bloc `backend`.

   ```hcl
   terraform {
     required_version = ">= 1.9"

     required_providers {
       google = {
         source  = "hashicorp/google"
         version = ">= 6.0"
       }
     }
   }

   provider "google" {
     project = "advanced-cloud-ai"
     region  = "europe-west1"

     add_terraform_attribution_label = false
   }

   import {
     to = google_cloud_run_v2_service.scorer
     id = "projects/advanced-cloud-ai/locations/europe-west1/services/team1-scorer"
   }
   ```

   Sans la ligne `add_terraform_attribution_label = false`, le fournisseur ajoute un libellé au
   service, et le plan annonce une modification.

   **Dans `infra/scorer/`, on ne lance ni `terraform apply` ni `terraform destroy` : le service
   appartient au socle.**

2. Initialisez le dossier, puis laissez Terraform écrire la configuration du service tel qu'il est :

   ```bash
   cd infra/scorer
   terraform init
   terraform plan -generate-config-out=scorer.tf
   ```

   L'option est expérimentale : le fichier généré peut demander une retouche. Elle refuse d'écrire
   sur un fichier existant : pour régénérer, supprimez d'abord `scorer.tf`.
3. Dans la ressource générée, ajoutez :

   ```hcl
     lifecycle {
       prevent_destroy = true
     }
   ```

   Relisez `scorer.tf` : les blocs `traffic` doivent nommer la révision en service et ses tags. Le
   bloc `template` décrit la **dernière révision créée** (`template.revision`), pas forcément celle
   qui sert le trafic : après un retour arrière, ce sont deux révisions différentes. Comparez
   `template.revision` à la révision qui porte 100 % dans les blocs `traffic`. Relancez le plan et
   enregistrez sa sortie :

   ```bash
   terraform plan -no-color | tee ../../docs/seance-6/plan.txt
   ```

   Si les deux révisions diffèrent, écrivez-le en une ligne en tête de `plan.txt` : le gabarit
   courant du service n'est pas celui qui sert, et il faut le savoir pour reconstruire le service.
4. `plan.txt` contient les adresses des comptes qui ont créé et modifié le service (`creator`,
   `last_modifier`). Votre fork est public : masquez-les avant le commit.

   ```bash
   sed -E 's/((creator|last_modifier)[[:space:]]*=[[:space:]]*)"[^"]*"/\1"<adresse>"/' \
     ../../docs/seance-6/plan.txt > plan.masque && mv plan.masque ../../docs/seance-6/plan.txt
   grep '@' ../../docs/seance-6/plan.txt | grep -v -e 'gserviceaccount\.com' -e '@sha256:'
   ```

   La dernière commande ne doit rien renvoyer. Les adresses qui restent dans `plan.txt` sont celles
   des comptes de service (elles finissent par `iam.gserviceaccount.com`) et, s'il y en a, les
   empreintes d'image (`@sha256:...`) : elles peuvent rester. `scorer.tf` ne contient ni
   `creator` ni `last_modifier`. Relancez ce masquage chaque fois que vous régénérez `plan.txt`.
5. **L'ombre**, dans `infra/release.tf`. Copiez le squelette :

   ```bash
   cd ..
   cp ../docs/seance-6/release.tf release.tf
   ```

   Il déclare la variable `shadow_tag`, vide par défaut, et l'abonnement
   `google_pubsub_subscription.shadow` avec `count = var.shadow_tag == "" ? 0 : 1` : vide, aucun
   abonnement ; renseignée, l'abonnement `team1-shadow` pousse vers `<adresse du tag>/pubsub/shadow`.
   L'adresse du tag est lue dans `traffic_statuses` de la source de données du service. Le topic, le
   compte de poussée et l'audience sont ceux de `shadow.sh`. Lisez cette partie : il n'y a rien à y
   compléter.
6. **L'alerte**, dans le même fichier. `google_monitoring_alert_policy.release` est la règle de la
   restitution : celle qui aurait détecté votre panne. Sa structure est écrite : nom
   `team1-scorer-release`, libellé `team`, une condition à seuil évaluée révision par révision de
   `team1-scorer`. Faites les trois choix marqués `À COMPLÉTER` :

   | Choix | Ce que vous écrivez |
   | --- | --- |
   | (1) le signal | le type de métrique, l'aligneur et le réducteur d'une des trois lignes en commentaire : latence Cloud Run, compteur `td6_scored` ou `td6_failed`, distribution `td6_score` |
   | (2) le seuil | une valeur dans l'unité de la métrique |
   | (3) la durée | combien de temps le seuil doit être franchi, un multiple de 60 s |

   Le projet n'a pas de canal de notification : la règle s'ouvre dans **Monitoring → Alertes**,
   sans envoi. Si vous avez déjà créé cette règle dans la console (extension « Alerte »),
   supprimez-la avant l'`apply`.
7. Depuis `infra/`, vérifiez, puis appliquez l'ombre et l'alerte seulement. Les `-target` évitent
   d'appliquer en même temps un écart laissé par une autre séance entre votre code et l'état réel.

   ```bash
   grep -n 'À COMPLÉTER' release.tf
   terraform fmt
   terraform validate
   terraform apply -target=google_pubsub_subscription.shadow -target=google_monitoring_alert_policy.release
   ```

   La commande `grep` ne doit rien renvoyer.
8. Testez l'ombre une fois, avec les mêmes `-target`, puis réappliquez sans la variable :

   ```bash
   terraform apply -var shadow_tag=candidate \
     -target=google_pubsub_subscription.shadow -target=google_monitoring_alert_policy.release
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="team1-scorer" AND jsonPayload.message="scored" AND jsonPayload.shadow=true' \
     --freshness 2m --limit 3 --format json
   terraform apply -target=google_pubsub_subscription.shadow -target=google_monitoring_alert_policy.release
   ```

   Le premier `apply` crée `team1-shadow`, le dernier le supprime.

**Ce que vous devez voir :** dans `plan.txt`, `google_cloud_run_v2_service.scorer` annoncé en import
(`will be imported`) et la ligne `Plan: 1 to import, 0 to add, 0 to change, 0 to destroy` ; pendant
le test, quelques lignes `scored` avec `shadow` vrai ; après le dernier `apply`, la règle d'alerte
dans **Monitoring → Alertes** et aucun abonnement `team1-shadow`.

**Si vous voyez...**

- Un écart du plan sur `terraform_labels` ou `effective_labels` : vérifiez la ligne
  `add_terraform_attribution_label = false` du bloc `provider` de `infra/scorer/main.tf`. Régénérer
  `scorer.tf` ne le corrige pas.
- Un autre écart, qui veut modifier ou remplacer le service : la configuration générée ne décrit plus
  l'état réel (trafic déplacé depuis, argument retiré à la main). Supprimez `scorer.tf` et
  régénérez-le ; n'appliquez rien.
- Une erreur de validation sur `scorer.tf` : retirez l'argument signalé, puis relancez le plan.

L'alias `champion` du registre reste hors de Terraform : c'est une décision de mise en service,
tracée par `promote.sh`, pas une ressource d'infrastructure.

## Livrable et évaluation

Remplissez dans votre fork, puis commit et push :

- `infra/release.tf`, `infra/scorer/main.tf`, `infra/scorer/scorer.tf` et `docs/seance-6/plan.txt` :
  l'état final en Terraform ;
- `docs/seance-6/mesures.md` : critères, références, tableau des paliers, réponses aux questions ;
- `docs/seance-6/validation.txt` : la sortie de `validate.sh` ;
- `docs/seance-6/post-mortem.md` : le post-mortem de la panne ;
- `docs/seance-6/checklist.md` : la checklist de préparation opérationnelle.

La checklist a six lignes. Trois sont alimentées par le parcours minimum, une par « Après le TD ».
Les deux autres ne le sont que par les extensions : une équipe qui ne les a pas faites répond « non » et écrit ce qui manque.
**Une ligne sans preuve est un non**, et c'est une réponse recevable.

| Ligne | Alimentée par | Preuve à joindre |
| --- | --- | --- |
| Validated | étape 2 | verdict de la validation, segment le plus faible, comparaison en ombre |
| Reversible | étapes 1, 3 et 5 | critères, tableau des paliers, retour arrière vérifié |
| Observed | étapes 0, 1 et 4 | référence, objectif de service, signal qui a détecté la panne |
| Degradable | extension « Mode dégradé » | repli observé, ou ce qui manque pour en décider |
| Restorable | « Après le TD » | `plan.txt` et les fichiers Terraform (`infra/release.tf`, `infra/scorer/`) |
| Owned | extension « Politique de réentraînement » | politique retenue et un responsable par ligne |

L'évaluation suit la grille de « Ce que vous saurez faire ».

## Fin de séance

Vérifiez que vous ne laissez ni ombre ni tag temporaire :

```bash
gcloud pubsub subscriptions list --filter 'name~team1-shadow' --format 'value(name)'
gcloud run services describe team1-scorer --region europe-west1 \
  --flatten 'status.traffic[]' \
  --format 'table(status.traffic.revisionName,status.traffic.tag,status.traffic.percent)'
```

La première commande ne doit rien renvoyer. La table du trafic doit montrer `candidate` (ou `champion` si vous avez refusé le challenger) à 100 %, et
aucun tag `next` ni `degrade`. Ne supprimez pas le service : il appartient au socle.
