# Mesures séance 6 — team1

## Valeurs de référence (étape 0)

| Mesure | Valeur |
| --- | --- |
| Heure du relevé ; fenêtre | ... ; 10 min |
| Révision en service (tag `champion`) | ... |
| Latence p95 (`p95 ms` de `measure.py`) | ... ms |
| Taux d'erreur (`erreurs`) | ... % |
| Taux d'alerte (`alertes`) | ... % |
| Âge du plus ancien message non acquitté (tableau de bord) | ... s |

## Critères (étape 1)

Heure à laquelle les critères sont figés : ...

Objectif de service : ... % des transactions scorées en moins de ... ms.

| Signal | Référence | Seuil d'avancement | Seuil de retour arrière | Source |
| --- | --- | --- | --- | --- |
| Latence p95 | ... ms | ... | ... | `measure.py`, `p95 ms` |
| Taux d'erreur | ... % | ... | ... | `measure.py`, `erreurs` |
| Taux d'alerte | ... % | ... | ... | `measure.py`, `alertes` |
| Âge du plus ancien message | ... s | ... | ... | tableau de bord |

Borne d'alertes fixée après l'ombre (étape 2) : ... ; écart d'alertes mesuré en ombre : ... points ; heure : ...

Durée d'observation par palier : ... min.

Commande de retour arrière (étapes 1 à 3) :

```bash
gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags champion=100
```

Commande de retour arrière (à partir du palier à 100 %) ; `champion=100` si vous avez refusé le challenger :

```bash
gcloud run services update-traffic team1-scorer --region europe-west1 --to-tags candidate=100
```

## Validation (étape 2)

| Mesure | Valeur |
| --- | --- |
| `contrat.ok` ; latence pour 1 000 lignes (champion, candidat) | ... ; ... ms, ... ms |
| AP globale champion, candidat ; écart et `ic95` | ... , ... ; ... [... ; ...] |
| Segment le plus faible ; son écart et son `ic95` | ... ; ... [... ; ...] |
| Segments non concluants | ... |
| `rejeu` : désaccord, taux d'alerte champion et candidat | ... , ... , ... |
| Révision candidate ; version du modèle | ... ; ... |
| Verdict | ... |

## Mesures par palier

Une ligne par palier, relevée à la fin de la durée d'observation. La révision mesurée est la
nouvelle (`candidate`, puis `next` pour la panne, puis `candidate` au retour) ; la révision de
comparaison est celle qui sert de référence au même moment (`champion` jusqu'au palier à 100 %,
`candidate` pour la panne). Chaque case de signal porte deux valeurs : mesurée / comparaison. Au
palier à 100 % et au retour, la révision de comparaison n'a plus de trafic : comparez à la
référence de l'étape 0.

| Palier | Début | Fin | Révision mesurée | Révision de comparaison | `tx distinctes` (mesurée / comparaison) | p95 ms (mesurée / comparaison) | Erreurs (mesurée / comparaison) | Alertes (mesurée / comparaison) | Âge du plus ancien message | Décision | Critère invoqué |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ombre (0 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 10 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 50 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| 100 % | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| Panne (`next` à 10 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |
| Retour (`candidate` ou `champion` à 100 %) | ... | ... | ... | ... | ... / ... | ... / ... | ... / ... | ... / ... | ... | ... | ... |

En ombre : désaccord ... % et écart d'alertes ... points (`--compare`), sur ... transactions
communes.

Panne : passage à 10 % à ... ; détection à ... ; délai ... min ; signal : ... (valeur ... , borne ...).

Alias `champion` du registre déplacé sur la version ... à ... .

## Réponses aux questions

### Étape 2 — Validation et ombre

1. Écart global, son intervalle, effet de l'avertissement : ...
2. Segments non concluants, et pourquoi ne pas fonder le verdict sur eux : ...
3. Désaccord en ombre comparé au `desaccord` de la validation, deux raisons d'écart : ...
4. Ce que l'ombre apprend que la validation ne pouvait pas apprendre : ...

### Étape 3 — Paliers

1. Transactions distinctes du candidat à 10 %, et si elles suffisent pour juger son taux d'alerte : ...
2. Signal le plus proche du seuil de retour arrière, et à quel palier : ...
3. Effet de `promote.sh` sur le trafic, et rôle de l'alias du registre : ...

### Étape 4 — Panne

1. Premier signal sorti de sa bande ; signaux qui n'ont pas bougé : ...
2. Signal qui aurait suffi seul ; signal qui ne l'aurait jamais vue : ...
3. Transactions traitées par la révision `next` avant la détection ; ce qu'elle en aurait traité à 100 % : ...
