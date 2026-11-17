# Compte rendu séance 4 — team1

| Mesure | Valeur |
| --- | --- |
| Lignes dans `tx_history`, transactions distinctes, doublons — dernier comptage du 1er octobre | 202 718 lignes, 100 859 `TX_ID` distincts, 101 859 lignes supplémentaires |
| Messages distincts — même comptage | 202 718 `message_id` distincts : publications répétées |
| Octets traités, avec puis sans filtre sur `TX_TS`, sans cache — dernières mesures | 13,34 MB puis 11,79 MB ; 14 MB puis 12 MB facturés |
| Requête filtrée servie depuis le cache | 126 ms ; 0 B traités et facturés ; exclue de la comparaison des lectures |
| Mesures initiales de Julius sur `tx_history` | Avec filtre : 7,0 Mo ; sans filtre : 6,2 Mo |
| Mesures initiales sur `tx_seed`, étape 0 | Avec filtre : 11,3 Mo ; sans filtre : 33,7 Mo |
| Résultat de `check.sql` | client : 0 ; terminal : 0 |
| Client `7989449428740969`, jour 2026-10-01 | `n = 5`, `amount_sum = 100,79` |
| Lecture des compteurs, source `parquet` | p50 : 0,780 ms ; p99 : 1,129 ms |
| Lecture des compteurs, source `bigquery` | p50 : 225,635 ms ; p99 : 284,005 ms |
| Lecture des compteurs, source `firestore` | p50 : 9,958 ms ; p99 : 16,374 ms |
| Score de la transaction `275114ca...`, source `parquet` | 0.00010230999760096893 |
| Score de la même transaction, sources `bigquery` et `firestore` | 0.00019268736650701612 pour les deux sources |
| Partie D : réglage retenu pour un rappel@10 ≥ 0,95 | `m = 16`, `ef = 8` ; rappel : 0,985 ; p50 : 0,40 ms ; p95 : 0,57 ms |
| Partie D : clients ayant présenté des variantes du même document que `0018478647296750` | `3263319564977208`, `2947552228922773`, `0553287702820053` |
| Dépôt Terraform et SQL | https://github.com/JuliusHayter/ai-cloud-infra-terraform-team-1 |

## Partie A — Historiser

### A.1 — Origine des doublons

Au premier comptage, la table contenait 101 359 lignes pour 100 859 transactions,
soit 500 lignes supplémentaires. Au dernier comptage, elle contient 202 718 lignes,
100 859 transactions distinctes et 202 718 messages distincts.

Tous les `message_id` sont distincts : les répétitions viennent de publications
multiples des mêmes transactions, et non de nouvelles livraisons du même message.
Une nouvelle livraison conserverait son `message_id`.

La déduplication doit donc utiliser l'identifiant métier `TX_ID`.

### A.2 — Le service de scoring était-il nécessaire ?

Non. L'abonnement BigQuery reçoit les messages de `ff-replay` et les écrit
directement dans `team1.tx_history`, indépendamment du service de scoring.

Si l'écriture était réalisée dans `/pubsub`, un arrêt du service empêcherait
l'historisation immédiate. Les messages resteraient en attente, avec un risque
de transfert vers la file de messages morts ou d'expiration selon les politiques
configurées. Le nombre maximal de tentatives de livraison est approximatif.

Deux abonnements séparent le scoring et l'archivage : une panne du service
de scoring ne bloque pas l'alimentation directe de BigQuery.

### A.3 — Pourquoi partitionner sur `TX_TS` ?

Les compteurs utilisent la date de la transaction, et non celle de sa publication.
Les transactions du 1er octobre ont été rejouées en novembre : `publish_time`
représente ici le rejeu, pas l'activité économique.

Partitionner sur `TX_TS` permet d'exclure les jours de transactions inutiles lors
des requêtes, même lorsque les messages arrivent en retard.

### Comparaison des octets traités

Lors des premières mesures, Julius a observé les données récentes dans
`__UNPARTITIONED__`. Le filtre ne permettait alors pas d'élaguer les partitions.

Lors de nos dernières mesures sans cache :
- avec filtre : 13,34 MB traités ;
- sans filtre : 11,79 MB traités.

Aucun gain de lecture n'est observé ici. Lorsque toutes les données correspondent
à la journée sélectionnée, le filtre n'exclut aucune partition utile ; il nécessite
aussi la lecture de `TX_TS`, absente des colonnes comptées sans filtre.

Les deux mesures ayant été réalisées à des instants différents, elles ne constituent
pas une comparaison parfaitement contrôlée sur une table immuable.

Sur `tx_seed`, les mesures initiales montrent l'intérêt du filtrage :
11,3 Mo contre 33,7 Mo pour sept jours sélectionnés sur vingt et un.

## Partie B — Agréger

Requêtes conservées :
- `infra/sql/customer_daily.sql`
- `infra/sql/terminal_daily.sql`

Le contrôle fourni renvoie 0 pour les clients et 0 pour les terminaux :
aucune ligne produite sur septembre ne diffère des références selon ce contrôle.

Le client `7989449428740969` possède bien une ligne au 1er octobre :
`n = 5`, `amount_sum = 100,79`.

### B.1 — Que se passe-t-il sans déduplication ?

Les publications répétées sont comptées comme des transactions supplémentaires :
les nombres de transactions et les sommes de montants sont alors surestimés.

Lors du premier rejeu, Julius avait observé 497 couples client-jour affectés
par les 500 publications supplémentaires. Le client de référence n'était alors
pas affecté.

Ces observations décrivent le premier état de la table. Après les publications
supplémentaires, leur effet exact sans déduplication n'a pas été remesuré.

Avec `GROUP BY TX_ID`, les compteurs restent fondés sur les transactions distinctes,
quel que soit le nombre de publications.

### B.2 — Où applique-t-on la limite à la veille ?

Au moment de la lecture par le service. La table conserve les compteurs de chaque
jour ; pour scorer une transaction du 2 octobre, le service utilise uniquement
les jours allant jusqu'au 1er octobre.

Lire le compteur complet du jour même pourrait inclure la transaction courante
et des transactions ultérieures. Cela introduirait une fuite temporelle et
rendrait le score dépendant du moment du recalcul.

### B.3 — Pourquoi `n_fraud = 0` pour le flux ?

Le flux ne contient pas de label `TX_FRAUD`. Les labels sont mis à `NULL`,
et `COUNTIF(TX_FRAUD = 1)` renvoie donc 0.

Cela signifie qu'aucune fraude n'est connue dans ces données, sans prouver
l'absence de fraude. Dans un système réel, les labels arrivent après contestation
ou enquête. Le décalage de sept jours vise à utiliser des labels suffisamment
anciens pour être disponibles au moment du scoring.

## Partie C — Servir

### Protocole

Nous avons testé successivement `parquet`, `bigquery` et `firestore`
avec l'image `ref-fraud-api:td4`.

Les compteurs BigQuery ont été copiés vers Firestore avec `publish_features.py`.

Pour chaque source :
- cinq appels de chauffe exclus ;
- cent appels HTTP séquentiels sur la même transaction de référence ;
- mesure du champ `timings_ms.features`, calculé par le serveur ;
- percentiles calculés par rang sur les cent observations.

Le temps réseau n'est pas inclus dans la durée des features.

Ce protocole remplace les mesures prévues sous rejeu Pub/Sub. Il ne mesure
ni la capacité sous charge concurrente ni l'accumulation de messages.
La répétition de la même transaction peut bénéficier de caches éventuels.
Le p99 reste une estimation sur un petit échantillon.

| Source | p50 (ms) | p99 (ms) |
| --- | --- | --- |
| Parquet | 0,780 | 1,129 |
| BigQuery | 225,635 | 284,005 |
| Firestore | 9,958 | 16,374 |

### C.1 — Pourquoi le score change-t-il ?

Le modèle reste identique, mais ses variables changent avec l'historique disponible.

Parquet s'arrête au 30 septembre. BigQuery et Firestore incluent les cinq
transactions du client du 1er octobre, utilisées pour scorer celle du 2 octobre.

BigQuery et Firestore donnent exactement le même score :
`0.00019268736650701612`, contre `0.00010230999760096893` pour Parquet.

### C.2 — Que perd-on avec Parquet ?

La lecture en mémoire est très rapide, mais l'historique est figé au démarrage.
Sans mécanisme de mise à jour, les nouvelles transactions ne sont pas intégrées.

Plusieurs instances peuvent également disposer de versions différentes
des fichiers si leur chargement n'est pas coordonné.

### C.3 — Pourquoi éviter BigQuery à chaque transaction ?

La lecture BigQuery est environ 23 fois plus lente que Firestore en médiane.

Avec 225,635 ms de lecture, un traitement strictement séquentiel représenterait
environ `1 / 0,225635 = 4,43` transactions par seconde, avant les autres coûts.

Ce calcul n'est pas une capacité mesurée par instance : la concurrence,
les quotas et les ressources influencent le débit réel. À 1 000 messages/s,
ces latences impliqueraient une forte concurrence et un dimensionnement adapté.

L'accumulation de messages Pub/Sub n'a pas été observée pendant notre protocole.

### C.4 — À quelle fréquence actualiser Firestore ?

Avec des features calculées par journées complètes jusqu'à la veille,
une actualisation quotidienne après clôture et agrégation est cohérente.

Un traitement orchestré doit vérifier la complétude, recalculer les agrégats,
publier les documents et gérer les reprises. Une exigence de fraîcheur intrajournalière
nécessiterait un autre rythme et une définition adaptée des features.

## Partie D — Recherche vectorielle

49 394 documents, représentés par des embeddings de 384 dimensions.
Mesures sur 300 recherches de dix voisins, durée mesurée côté serveur.

### Index `m = 16`

Envoi des documents : 91 s.
Construction de l'index après envoi : 104 s.
`ef_construct = 100`.

| ef | rappel@10 | p50 (ms) | p95 (ms) |
| --- | --- | --- | --- |
| exact | 1,000 | 9,18 | 10,77 |
| 4 | 0,985 | 0,43 | 0,59 |
| 8 | 0,985 | 0,40 | 0,57 |
| 16 | 0,986 | 0,42 | 0,58 |
| 32 | 0,993 | 0,49 | 0,65 |
| 64 | 1,000 | 0,61 | 0,79 |
| 128 | 1,000 | 0,79 | 1,08 |
| 256 | 1,000 | 1,04 | 1,38 |

### Index `m = 4`

Envoi des documents : 106 s.
Construction de l'index après envoi : 119 s.
`ef_construct = 100`.

| ef | rappel@10 | p50 (ms) | p95 (ms) |
| --- | --- | --- | --- |
| exact | 1,000 | 10,20 | 14,99 |
| 4 | 0,659 | 0,38 | 0,68 |
| 8 | 0,659 | 0,37 | 0,69 |
| 16 | 0,685 | 0,39 | 0,57 |
| 32 | 0,756 | 0,46 | 0,79 |
| 64 | 0,832 | 0,52 | 0,78 |
| 128 | 0,905 | 0,69 | 1,21 |
| 256 | 0,944 | 0,90 | 1,39 |

### Réglage retenu

Nous retenons `m = 16`, `ef = 8` : rappel de 0,985,
p50 de 0,40 ms et p95 de 0,57 ms.

C'est la plus faible latence médiane observée parmi les configurations
satisfaisant le rappel minimal de 0,95. Les différences de quelques centièmes
de milliseconde entre les petits `ef` restent faibles et peuvent varier entre essais.

Aucun réglage testé avec `m = 4` n'atteint l'objectif.
Le réglage retenu est une recommandation issue des mesures ;
le dernier index effectivement chargé utilise encore `m = 4`.

### Documents réutilisés

La recherche du document 87 a retrouvé trois variantes du bulletin de paie
associé au client `0018478647296750` :

| Client | Similarité affichée |
| --- | --- |
| `3263319564977208` | 0,9997 |
| `2947552228922773` | 0,9996 |
| `0553287702820053` | 0,9990 |

Le nom, l'employeur, la période et l'adresse sont identiques ;
le salaire net a été modifié. Ces ressemblances justifient une vérification,
sans constituer seules une preuve de fraude.

### D.1 — Effets de `ef` et `m`

Avec `m = 4`, augmenter `ef` de 4 à 256 fait passer le rappel de 0,659
à 0,944, et la médiane de 0,38 à 0,90 ms : davantage de candidats sont explorés.

À `ef` égal, `m = 16` améliore nettement le rappel dans nos mesures.
Un graphe plus connecté nécessite généralement davantage de mémoire.
Nos temps de construction ne montrent toutefois pas un avantage pour `m = 4` :
119 s contre 104 s pour `m = 16`.

### D.2 — Quand l'index devient-il nécessaire ?

Il n'existe pas de seuil universel : cela dépend du volume, du débit demandé,
du matériel et de la latence acceptable.

La recherche exacte lit tous les vecteurs ; son travail croît approximativement
avec leur nombre à dimension constante. À matériel et conditions comparables,
un million de documents pourrait représenter environ vingt fois le travail
observé sur 49 394 documents. L'index devient utile lorsque ce coût dépasse
le budget de latence ou de calcul.

### D.3 — Un rappel de 0,95 est-il acceptable ?

Il signifie qu'en moyenne 95 % des dix vrais voisins sont retrouvés sur le test,
sans garantir la détection de chaque document réutilisé.

Pour une aide à l'analyste, ce compromis peut être acceptable.
Pour une détection critique, il faut mesurer spécifiquement les faux négatifs
sur les réutilisations recherchées et envisager une recherche plus exhaustive.

### D.4 — Scaling et persistance

Nous avons configuré :
- `min_instance_count = 1` ;
- `max_instance_count = 1`.

Cela évite le passage automatique à zéro et la répartition des requêtes
entre plusieurs instances ayant chacune leur stockage local.

Cette configuration ne garantit pas la persistance : un redémarrage ou
un remplacement de l'instance peut faire perdre les données et l'index.
Il faut alors relancer le chargement. Une exploitation durable nécessiterait
un stockage persistant adapté ou un service vectoriel géré.

### D.5 — Changer de modèle d'embedding

Il faut recalculer les embeddings de tous les documents et reconstruire l'index.
Les requêtes doivent utiliser le même modèle, le même prétraitement
et une configuration de collection compatible avec la nouvelle dimension.

## Conclusion

Nous garderions Firestore pour servir les compteurs en direct : il fournit
le même score actualisé que BigQuery avec une médiane de lecture d'environ 10 ms.
BigQuery conserverait l'historique et calculerait les agrégats, ensuite publiés
régulièrement vers Firestore.