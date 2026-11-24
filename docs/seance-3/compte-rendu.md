# Compte rendu séance 3 — team1

| Mesure | Valeur |
| --- | --- |
| Messages traités et débit atteint | environ 384 000 messages acquittés entre 17:58 et 18:13 (somme des acquittements de `team1-tx-push`, autant que de messages publiés dans `ff-replay`) ; palier le plus haut suivi sans retard qui grossit : 500 messages/s |
| Âge maximal du plus ancien message non acquitté pendant la montée en charge | 148 s, au palier de 1 000 messages/s (pendant la vidange de la file, 18:12) ; 18 s au plus au palier de 500 messages/s |
| Nombre d'instances au pic | 3 (maximum autorisé : 3), atteint dès 17:59, au palier de 100 messages/s |
| `tx_id` lu dans la file de messages morts | `poison-20261116` (`message_id` 23290635766501881), arrivé environ 1,2 min après la publication : première livraison à 17:57:46, cinquième et dernière à 17:59:00, `dead_letter_message_count` = 1 sur la minute 17:59-18:00 |
| Lien du dépôt (Terraform et service) | <https://github.com/JuliusHayter/ai-cloud-infra-terraform-team-1> et <https://github.com/JuliusHayter/team1-td2-fraud-api-albertschool> |

## Étape 1 — Brancher

Observé le 12/11, entre 18 h 45 et 19 h 04 UTC environ, avant le déploiement de `/pubsub` : au moins
1 000 tentatives en échec sur `POST /pubsub` (139 en 403 pendant la propagation du droit d'appel,
puis 861 en 404), et 283 messages envoyés en file de messages morts
(`subscription/dead_letter_message_count` de `team1-tx-push`, autant reçus par `team1-tx-dead`).

**1.1 — Messages non acquittés et âge du plus ancien message pendant les 404.** Les deux courbes
montent : un 404 n'est pas un 2xx, donc aucun message n'est acquitté et ils s'accumulent au rythme du
topic (environ 0,6 message/s). L'âge du plus ancien message plafonne au lieu de croître sans fin :
après 5 tentatives (10 à 60 s d'attente entre deux), chaque message part dans `team1-tx-dead` et
quitte l'abonnement. Sans file de messages morts, il monterait jusqu'à la rétention de l'abonnement
(1 h), puis les messages seraient supprimés sans trace.

**1.2 — Pourquoi un compte `team1-push` séparé de `team1-run`.** Ce sont deux rôles différents :
`team1-run` est l'identité sous laquelle tourne le code, `team1-push` celle avec laquelle Pub/Sub
s'authentifie pour appeler le service.

| Compte | Droits |
| --- | --- |
| `team1-run` | `roles/storage.objectViewer` sur le bucket des modèles, `roles/logging.logWriter` sur le projet |
| `team1-push` | `roles/run.invoker` sur le seul service `team1-fraud-api` |

Moindre privilège : chaque identité n'a que ce dont elle a besoin. Signer avec `team1-run`
obligerait à lui donner `run.invoker` (le code pourrait s'appeler lui-même), et l'identité de
livraison aurait accès au bucket des modèles. Un jeton `team1-push` qui fuit ne permet que
d'appeler ce service, sans accès aux données. La politique IAM du service montre aussi clairement
qui peut l'appeler : `team1-push` et nos comptes.

**1.3 — Contenu de `team1-tx-dead-pull` après 3 minutes.** Des transactions FraudFinder valides,
au même format que le flux, avec les attributs ajoutés par Pub/Sub
`CloudPubSubDeadLetterSourceSubscription = team1-tx-push` et
`CloudPubSubDeadLetterSourceDeliveryCount = 5`. Elles n'étaient pas mauvaises : le service ne
savait pas les recevoir (`/pubsub` absent, donc 404), et après 5 échecs la `dead_letter_policy` les
a déplacées dans `team1-tx-dead`. C'est pourquoi l'étape 3 commence par vider cette file (`seek`).

## Étape 2 — Adapter

`POST /pubsub` ajouté dans `app.py` du service : décodage base64 puis JSON, validation de la
transaction (422 et log `rejected` si invalide), score avec `record=False`, une ligne JSON `scored`,
puis 204 seulement après le log. Testé en local (204 sur `enveloppe.json`, 422 sur `TX_AMOUNT: -1`),
puis déployé : sur `team1-tx-push`, uniquement des 204 et une ligne `scored` par transaction avec
`delivery_attempt = 1`.

## Étape 3 — Observer et casser

Mesures du 16/11, relues après coup dans Cloud Monitoring (métriques de `team1-tx-push`, du topic
`ff-replay` et de `team1-fraud-api`) et dans Cloud Logging. Heures de Paris (UTC + 1). Le message
empoisonné est établi par les logs `rejected` du service et par la métrique de lettre morte ; sa
lecture dans `team1-tx-dead-pull` avec `--auto-ack` n'a pas été conservée.

| Minute | Publié dans `ff-replay` (msg/s) | Acquitté (msg/s) | Messages non délivrés (max) | Âge du plus ancien (s) | Instances |
| --- | --- | --- | --- | --- | --- |
| 17:59-18:01 | 100 | 97 à 108 | 0 | 0 | 3 |
| 18:02 | 318 | 288 | 20 | 0 | 3 |
| 18:03-18:05 | 495 à 500 | 499 à 501 | 428, puis 74 et 95 | 6, puis 18, puis 0 | 3 |
| 18:06 | 756 | 574 | 2 980 | 4 | 3 |
| 18:07-18:09 | 977 à 1 000 | 506 à 706 | 24 244, 45 117, 67 572 | 60, puis 78 | 3 |
| 18:10-18:12 | 478, 20, 0 | 502 à 686 | 86 288 (pic), 49 030, 11 115 | 110, 132, 148 | 3 |
| 18:13 | 0 | 41 | 0 | 0 | 3 |

Au palier de 1 000 messages/s, Cloud Run refuse une partie des requêtes de Pub/Sub avec `429 Too
Many Requests` (au moins 3 000 réponses 429 entre 18:05 et 18:14) : aucune instance n'a de place.
Pub/Sub les relivre : au moins 5 000 lignes `scored` avec `delivery_attempt` = 2 (et 64 à 3), toutes
entre 18:07 et 18:11.

**3.1 — À quel débit le retard grossit-il, et qu'est-ce qui l'absorbe ?** Le retard grossit au palier
de 1 000 messages/s : la file passe de 2 980 à 86 288 messages en quatre minutes et l'âge du plus
ancien message monte à 148 s, car le service plafonne entre 500 et 700 messages/s alors qu'on en
publie 1 000. À 500 messages/s, la file monte brièvement (428) puis redescend : le service suit. Ce
n'est pas la concurrence par instance qui limite (`max_instance_request_concurrency = 80` dans
`main.tf`) : avec 1 vCPU et `WEB_CONCURRENCY=1`, chaque instance est bornée par son CPU, environ
170 à 230 messages/s. C'est le nombre maximal d'instances (`max_instance_count = 3`), atteint dès
le palier de 100 messages/s, qui fixe le plafond : au-delà, Cloud Run répond 429. Ce qui absorbe
l'excédent, c'est l'abonnement Pub/Sub : les messages attendent dans la file, puis sont vidés après
la fin du pic (18:10-18:13), sans perte. Pour suivre 1 000 messages/s, il faudrait plus d'instances
(au moins 5 à 6) ou des instances plus puissantes.

**3.2 — Sans file de messages morts, que serait devenu le message empoisonné ?** Il est invalide
(`TX_AMOUNT: -1`), donc `/pubsub` le refuse toujours en 422. Avec la file de messages morts, il a été
écarté après 5 tentatives, en 1 min 14 s (17:57:46 puis 17:59:00), et conservé pour être lu. Sans
elle, Pub/Sub l'aurait relivré sans fin, toutes les 10 à 60 s, jusqu'à la fin de la rétention de
l'abonnement (`message_retention_duration = 3600s`), soit une centaine de tentatives inutiles, puis
il aurait été supprimé sans trace hors des logs. Pendant cette heure, il aurait aussi maintenu
l'âge du plus ancien message non acquitté à une valeur élevée, masquant un vrai retard du service.

**3.3 — Doublons de `tx_id` : comment les vérifier, et distinguer une nouvelle livraison d'une
seconde publication ?** On les vérifie en comptant les `tx_id` des lignes `scored` :

```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="team1-fraud-api" AND jsonPayload.message="scored"' \
  --freshness 1h --limit 10000 --format 'value(jsonPayload.tx_id)' | sort | uniq -d
```

Pendant la charge, il y a eu au moins 5 000 nouvelles livraisons (`delivery_attempt` ≥ 2). Pour
celles qu'on a examinées (`8e82b45c…`, `152bc8ec…`), il n'existe aucune ligne `scored` pour la
première tentative : elle a été refusée en 429 par Cloud Run avant d'atteindre le code. Ce ne sont
donc pas des doublons dans les logs. Un vrai doublon apparaîtrait si le service avait scoré et
journalisé le message, mais que l'acquittement s'était perdu (les `deadline_exceeded` de la
métrique, très rares ici) : c'est pour cela que `/pubsub` ne fait que scorer avec `record=False`,
pour qu'une nouvelle livraison donne le même score. Pour distinguer les deux cas : une nouvelle
livraison par Pub/Sub garde le même `message_id` et a `delivery_attempt` > 1 ; une seconde
publication a un autre `message_id` et `delivery_attempt` = 1 (c'est ce qu'on a observé à la
séance 4 : 500 transactions republiées avec deux `message_id` différents). Notre ligne `scored` ne
journalise pas `message_id` (seule la ligne `rejected` le fait) : l'ajouter rendrait la
distinction directe.
