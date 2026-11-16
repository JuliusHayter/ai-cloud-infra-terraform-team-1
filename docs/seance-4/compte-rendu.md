# Compte rendu séance 4 — team1

| Mesure | Valeur |
| --- | --- |
| Lignes dans `tx_history`, transactions distinctes, doublons | 101 359 lignes, 100 859 `TX_ID` distincts, 500 doublons |
| Octets traités par votre requête de comptage, avec puis sans filtre sur `TX_TS` | 7,0 Mo, 6,2 Mo (10 Mo facturés dans les deux cas, minimum par requête) ; sur `tx_seed` à l'étape 0 : 11,3 Mo avec filtre, 33,7 Mo sans |
| Résultat de `check.sql` | client : 0 ; terminal : 0 |
| Client `7989449428740969`, jour 2026-10-01 dans `customer_daily` | `n` = 5 , `amount_sum` = 100,79 |
| Lecture des compteurs, source `parquet` (p50, p99) | ... ms, ... ms |
| Lecture des compteurs, source `bigquery` (p50, p99) | ... ms, ... ms |
| Lecture des compteurs, source `firestore` (p50, p99) | ... ms, ... ms |
| Score de la transaction `275114ca...` : `parquet`, `firestore` | ... , ... |
| Partie D : réglage retenu pour un rappel@10 ≥ 0,95 | `m` = ... , `ef` = ... ; rappel ... ; p50 ... ms, p95 ... ms |
| Partie D : clients ayant présenté le même document que `0018478647296750` | ... , ... , ... |
| Lien du dépôt (Terraform et SQL) | <https://github.com/JuliusHayter/ai-cloud-infra-terraform-team-1> |

## Partie A — Questions

Mesures du 16/11 : les 101 359 lignes ont été publiées entre 18:52:42 et 18:56:08 UTC, et portent
toutes une `TX_TS` du 1er octobre 2026. Juste après le rejeu, elles étaient toutes dans la partition
`__UNPARTITIONED__` (données récentes pas encore réorganisées par BigQuery) : le filtre sur `TX_TS`
n'élaguait donc rien, et l'ajout de la colonne `TX_TS` à lire rendait même la requête filtrée un peu
plus chère. L'effet de la partition se voit sur `tx_seed` : 7 jours sur 21 lus, un tiers des octets.

**A.1 — Les doublons ont-ils le même `message_id` ?** Non. Les 500 `TX_ID` en double apparaissent
chacun sur exactement deux lignes, avec deux `message_id` différents, et des `publish_time` séparés
d'environ 3 min 30 (18:52 puis 18:56). Ce sont donc des **secondes publications** : la même
transaction a été publiée deux fois dans le topic. Une nouvelle livraison par Pub/Sub garderait le
même `message_id`. D'où le `GROUP BY TX_ID` de la partie B : on dédoublonne sur l'identifiant
métier, pas sur l'identifiant du message.

**A.2 — Le service était-il nécessaire ?** Non. Pendant tout le rejeu, notre abonnement push lisait
`ff-tx` : le service n'a vu passer aucun de ces messages, et la table s'est pourtant remplie.
L'abonnement BigQuery écrit lui-même dans la table. Si l'historisation avait été une ligne de code
dans `/pubsub` et que le service avait été arrêté, rien n'aurait été écrit : les messages seraient
restés non acquittés, relivrés, puis envoyés en file de messages morts après 5 échecs ou perdus à la
fin de la rétention. L'historique dépendrait aussi du scoring : un bug ou une saturation du service
ferait perdre l'archive. Séparer les deux abonnements découple les deux usages.

**A.3 — Pourquoi partitionner sur `TX_TS` plutôt que sur `publish_time` ?** Les transactions datent
du 1er octobre 2026, mais elles ont toutes été publiées le 16 novembre, en moins de 4 minutes.
Partitionné sur `publish_time`, tout le rejeu tomberait dans une seule partition (le jour de la
publication), et une requête « les 7 derniers jours de transactions » ne pourrait rien élaguer.
Les compteurs de la partie B sont calculés par jour de transaction : c'est donc `TX_TS` qui doit
découper la table, pour que le filtre de date lise seulement les jours utiles, quel que soit le
moment où les données arrivent (rejeu, retard, rattrapage).

## Partie B — Questions

Requêtes : `infra/sql/customer_daily.sql` et `infra/sql/terminal_daily.sql`. `check.sql` renvoie
0 et 0 : sur septembre, nos compteurs sont identiques aux fichiers parquet.

**B.1 — Lire `tx_history` directement dans `tx`, sans passer par `flux`.** Les 500 transactions
publiées deux fois sont alors comptées deux fois. Pour le client `7989449428740969`, `n` reste à 5
et `amount_sum` à 100,79 : aucune de ses transactions du 1er octobre n'a été republiée. Mais
497 couples (client, jour) seraient faux, par exemple le client `0056175802989811` : `n` = 6 au
lieu de 5, et son montant moyen serait faussé d'autant. Le modèle verrait un client plus actif
qu'il ne l'est. Le `GROUP BY TX_ID` de `flux` dédoublonne sur l'identifiant de la transaction.

**B.2 — Où est appliquée la règle « ne lire que les jours jusqu'à la veille » ?** Au moment de la
lecture, pas dans la table. La table garde un compteur par jour, y compris celui du jour même ;
c'est le service qui, pour une transaction du 2 octobre à 9 h, ne somme que les jours jusqu'au
1er octobre. Si le compteur du jour même était lu, il contiendrait des transactions postérieures
à 9 h (et la transaction elle-même) : c'est une fuite temporelle. Le modèle verrait au scoring en
direct des valeurs qu'il ne pourrait pas connaître, différentes de celles de l'entraînement, et
le score ne serait pas reproductible selon l'heure à laquelle on le recalcule.

**B.3 — `n_fraud` vaut 0 pour le 1er octobre : est-ce une erreur ?** Non. Le flux ne porte pas de
label `TX_FRAUD` : `n` vaut 100 859 ce jour-là, mais `n_fraud` vaut 0, contre 1 265 à 1 578 par
jour fin septembre (données du socle, labellisées). Dans un vrai système, on ne sait qu'une
transaction était frauduleuse qu'après coup : contestation du client, rétrofacturation, enquête,
ce qui prend des jours ou des semaines. Le service ne lit donc le taux de fraude d'un terminal
qu'avec 7 jours de retard, pour n'utiliser que des labels déjà connus, comme à l'entraînement.
Lire le taux du jour donnerait un 0 trompeur, qui ferait passer chaque terminal pour sain.

## Partie D — Mesures

Collez ici les deux tableaux de `measure` (`m = 16`, puis `m = 4`).

## Conclusion

En deux phrases : quelle source garderiez-vous pour scorer en direct, et pourquoi ?
