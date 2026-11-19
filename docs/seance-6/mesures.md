# Mesures séance 6 — team1

## Valeurs de référence (étape 0)

| Mesure | Valeur |
| --- | --- |
| Heure du relevé ; fenêtre | 19/11/2026 19:27 (heure de Paris) ; 10 min |
| Révision en service (tag `champion`) | `team1-scorer-prep-1119180441` (100 % du trafic) |
| Latence p95 (`p95 ms` de `measure.py`) | 2,6 ms (p50 : 1,7 ms) |
| Taux d'erreur (`erreurs`) | 0,0 % |
| Taux d'alerte (`alertes`) | 11,6 % |
| Âge du plus ancien message non acquitté (tableau de bord) | 0 s |

`measure.py` sur 10 min : n = 5 952 livraisons, 5 952 transactions distinctes (aucune relivraison),
score moyen 0,005, 0,0 % de dégradés.

## Critères (étape 1)

Heure à laquelle les critères sont figés : 19/11/2026 19:41 (heure de Paris), avant tout déploiement.

Objectif de service : 95 % des transactions scorées en moins de 10 ms, mesuré par `latency_ms`
(temps de traitement dans le service, colonne `p95 ms` de `measure.py`). La latence du tableau de
bord (`request_latencies`, environ 9,5 ms) inclut en plus le passage par la plateforme Cloud Run :
elle sert à surveiller, pas à décider.

| Signal | Référence | Seuil d'avancement | Seuil de retour arrière | Source |
| --- | --- | --- | --- | --- |
| Latence p95 | 2,6 ms | ≤ 5 ms | > 10 ms | `measure.py`, `p95 ms` |
| Taux d'erreur | 0,0 % | ≤ 0,5 % | > 1 % | `measure.py`, `erreurs` |
| Taux d'alerte | 11,6 % | entre 7,5 % et 15,5 % (provisoire) | < 5,5 % ou > 17,5 % (provisoire) | `measure.py`, `alertes` |
| Âge du plus ancien message | 0 s | < 30 s | ≥ 60 s | tableau de bord |

Règle : on avance si les quatre signaux de la nouvelle révision sont dans leur seuil d'avancement ;
on revient en arrière dès qu'un signal franchit son seuil de retour arrière, confirmé sur la fenêtre
complète ; entre les deux, on prolonge une seule fois de 5 min, puis on revient en arrière si le
doute persiste.

Justification des seuils (à 10 % du trafic, 5 min donnent environ 300 transactions) :

- Latence : 5 ms, soit environ deux fois la référence, laisse de la marge à un modèle plus lourd ;
  10 ms est l'objectif de service. La grille de repli (1,5 × 2,6 = 3,9 ms) est trop serrée : sur
  300 messages, la p95 repose sur une quinzaine de requêtes, et un démarrage à froid suffit à la
  déplacer de plus d'une milliseconde.
- Erreurs : la référence est de 0 sur 5 952 livraisons. On tolère une erreur isolée sur 300
  (0,33 %), possible au démarrage d'une instance ; au-delà de 1 % (4 erreurs ou plus), des
  transactions ne sont plus scorées.
- Alertes : sur 300 transactions à 11,6 %, l'écart-type est d'environ 1,85 point ; le hasard seul
  donne de 7,9 % à 15,3 %. Le seuil de retour arrière reprend la grille de repli (de la moitié à une
  fois et demie la référence). Bornes à recentrer après l'ombre sur l'écart d'alertes mesuré.
- Âge du plus ancien message : au démarrage d'une révision, quelques messages refusés sont relivrés
  après 10 à 60 s ; au-delà d'une minute, le service ne suit plus le flux. Ce signal porte sur tout
  l'abonnement, pas sur une révision : il confirme, il ne désigne pas la révision fautive.

Borne d'alertes fixée après l'ombre (étape 2) : avancement entre 11,4 % et 19,4 %, retour arrière
sous 9,4 % ou au-dessus de 21,4 % (taux d'alerte du candidat en ombre, 15,4 %, ± 4 et ± 6 points) ;
écart d'alertes mesuré en ombre : + 4,1 points ; heure : 20:01. Les bornes provisoires (17,5 %)
auraient déclenché un retour arrière sur un écart qui vient du modèle, pas d'une panne.

Durée d'observation par palier : 5 min (environ 300 messages pour la nouvelle révision à 10 % ; au
delà de 6 min, les trois paliers ne tiennent pas dans l'étape 3).

Commande de retour arrière (étapes 1 à 3) :

```bash
gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags champion=100
# ou, en nommant la révision :
gcloud run services update-traffic team1-scorer --region europe-west1 --to-revisions team1-scorer-prep-1119180441=100
```

Commande de retour arrière (à partir du palier à 100 %) ; `champion=100` si vous avez refusé le challenger :

```bash
gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=100
```

## Validation (étape 2)

| Mesure | Valeur |
| --- | --- |
| `contrat.ok` ; latence pour 1 000 lignes (champion, candidat) | `true` (20 features, noms identiques) ; 8,97 ms, 20,17 ms |
| AP globale champion, candidat ; écart et `ic95` | 0,8473 , 0,8854 ; + 0,0381 [0,0333 ; 0,0429] |
| Segment le plus faible ; son écart et son `ic95` | activité client 7 j ≥ 20 ; + 0,0212 [0,0159 ; 0,0268] |
| Segments non concluants | aucun : les six segments ont plus de 30 fraudes (565 à 2 211) |
| `rejeu` : désaccord, taux d'alerte champion et candidat | 7,6 % , 13,8 % , 13,4 % |
| Révision candidate ; version du modèle | `team1-scorer-candidate-1119195742` (tag `candidate`), version 2. Une première révision `team1-scorer-candidate-1119194814`, même modèle et mêmes variables, a été déployée à 19:48 puis remplacée à 19:59 par un second `release.sh` ; l'ombre a surtout été mesurée sur la première |
| Verdict | **Accepté pour le déploiement par paliers.** Contrat respecté ; écart global favorable avec un intervalle qui exclut 0 ; les six segments sont concluants et tous favorables, y compris le plus faible ; en ombre, 0 erreur et p95 de 3,2 ms, sous le seuil d'avancement de 5 ms. Réserves : les écarts de validation sont optimistes (août a servi au réglage), et en ombre le candidat alerte 4,1 points de plus que le champion, alors qu'il alertait légèrement moins en validation : borne d'alertes recentrée, signal à surveiller en priorité aux paliers |

## Mesures par palier

Une ligne par palier, relevée à la fin de la durée d'observation. La révision mesurée est la
nouvelle (`candidate`, puis `next` pour la panne, puis `candidate` au retour) ; la révision de
comparaison est celle qui sert de référence au même moment (`champion` jusqu'au palier à 100 %,
`candidate` pour la panne). Chaque case de signal porte deux valeurs : mesurée / comparaison. Au
palier à 100 % et au retour, la révision de comparaison n'a plus de trafic : comparez à la
référence de l'étape 0.

| Palier | Début | Fin | Révision mesurée | Révision de comparaison | `tx distinctes` (mesurée / comparaison) | p95 ms (mesurée / comparaison) | Erreurs (mesurée / comparaison) | Alertes (mesurée / comparaison) | Âge du plus ancien message | Décision | Critère invoqué |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ombre (0 %) | ≈ 19:52 | ≈ 20:00 | `team1-scorer-candidate-1119194814` (puis `…1119195742`) | `team1-scorer-prep-1119180441` | 4 642 / 4 751 | 3,2 / 2,5 | 0,0 % / 0,0 % | 15,4 % / 11,4 % | ... s (à lire) | avancer au palier 10 % | p95 ≤ 5 ms, erreurs ≤ 0,5 % ; alertes dans la borne recentrée après l'ombre |
| 10 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 50 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 100 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| Panne (`next` à 10 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| Retour (`candidate` ou `champion` à 100 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |

En ombre : désaccord 8,1 % et écart d'alertes + 4,1 points (`--compare`), sur 4 733 transactions
communes.

Panne : passage à 10 % à ... ; détection à ... ; délai ... min ; signal : ... (valeur ... , borne ...).

Alias `champion` du registre déplacé sur la version ... à ... .

## Réponses aux questions

### Étape 2 — Validation et ombre

1. Écart global, son intervalle, effet de l'avertissement : l'écart est en faveur du challenger
   (AP 0,8854 contre 0,8473, + 0,038) et son intervalle [0,033 ; 0,043] exclut 0 : sur août, le
   challenger est meilleur. Mais août a servi à choisir ses hyperparamètres : il a été réglé sur ces
   données, donc l'écart est optimiste. Il prouve que le challenger n'est pas moins bon, pas de
   combien il est meilleur ; seul le jeu de test (`train.gate`) tranche. D'où l'ombre et les paliers.
2. Segments non concluants, et pourquoi ne pas fonder le verdict sur eux : aucun ici, les six
   segments comptent de 565 à 2 211 fraudes. Un segment sous 30 fraudes donnerait une AP calculée
   sur trop peu de cas positifs : son écart pourrait changer de signe avec quelques fraudes de plus.
   Le verdict s'appuie sur le segment concluant le plus faible (activité client 7 j ≥ 20,
   + 0,021 [0,016 ; 0,027]), favorable lui aussi.
3. Désaccord en ombre comparé au `desaccord` de la validation, deux raisons d'écart : proches,
   8,1 % en ombre contre 7,6 % en validation. En revanche, le sens de l'écart d'alertes diffère :
   en validation le candidat alerte un peu moins (13,4 % contre 13,8 %), en ombre il alerte plus
   (15,4 % contre 11,4 %). Raisons : (a) les données ne sont pas les mêmes : août en validation, le
   rejeu de la séance en ombre, avec une autre distribution de montants et de clients ; (b) les
   features ne viennent pas du même endroit : calculées hors ligne pour la validation, lues par le
   service dans un instantané BigQuery (`source: bigquery`, `reader: snapshot`) en ombre, avec une
   fraîcheur différente. S'y ajoute la taille : 4 733 transactions en ombre contre 311 624.
4. Ce que l'ombre apprend que la validation ne pouvait pas apprendre : le comportement du
   challenger dans le vrai service, sur le vrai flux : il démarre, lit ses features sans erreur
   (0 % d'erreur, 0 % de dégradés), tient la latence (p95 3,2 ms contre 2,5 ms ; la validation
   annonçait un calcul 2,2 fois plus lent, mais il ne pèse que 0,02 ms par transaction), et son
   taux d'alerte réel sur le flux du moment (+ 4,1 points), qui a permis de recentrer la borne.
   Le tout sans qu'aucune de ses décisions ne touche la production.

### Étape 3 — Paliers

1. Transactions distinctes du candidat à 10 %, et si elles suffisent pour juger son taux d'alerte : ...
2. Signal le plus proche du seuil de retour arrière, et à quel palier : ...
3. Effet de `promote.sh` sur le trafic, et rôle de l'alias du registre : ...

### Étape 4 — Panne

1. Premier signal sorti de sa bande ; signaux qui n'ont pas bougé : ...
2. Signal qui aurait suffi seul ; signal qui ne l'aurait jamais vue : ...
3. Transactions traitées par la révision `next` avant la détection ; ce qu'elle en aurait traité à 100 % : ...
