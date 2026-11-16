# Compte rendu séance 3 — team1

| Mesure | Valeur |
| --- | --- |
| Messages traités et débit atteint | ... messages ; palier le plus haut suivi sans retard qui grossit : ... messages/s |
| Âge maximal du plus ancien message non acquitté pendant la montée en charge | ... s, au palier de ... messages/s |
| Nombre d'instances au pic | ... (maximum autorisé : 3) |
| `tx_id` lu dans la file de messages morts | ... , arrivé ... min après la publication |
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

**3.1 — À quel débit le retard grossit-il, et qu'est-ce qui l'absorbe ?** ...

**3.2 — Sans file de messages morts, que serait devenu le message empoisonné ?** ...

**3.3 — Doublons de `tx_id` : comment les vérifier, et distinguer une nouvelle livraison d'une
seconde publication ?** ...
