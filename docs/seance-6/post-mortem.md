# Post-mortem séance 6 — team1

Un post-mortem sans blâme décrit des mécanismes, pas des personnes : ce que le système a permis, ce
qu'il n'a pas vu, ce qui l'aurait vu plus tôt. Chaque affirmation renvoie à une mesure, un extrait de
log ou une courbe.

Résumé en une phrase : ...

## 1. Chronologie

| Heure | Événement | Source |
| --- | --- | --- |
| ... | révision `next` déployée sans trafic ; `/health` : ... | sortie de `release.sh` |
| ... | `next` passe à 10 % | commande `update-traffic` |
| ... | premier écart visible sur ... | `measure.py` ou tableau de bord |
| ... | détection : ... franchit le seuil de retour arrière | `mesures.md` |
| ... | cause identifiée | extrait de log ou courbe |
| ... | retour arrière : `candidate` à 100 % | commande `update-traffic` |
| ... | quatre signaux revenus dans leur bande | `measure.py` |

## 2. Signal

- Signal qui a détecté la panne : ... (valeur ... , borne ... , référence ...).
- Délai entre le passage à 10 % et la détection : ... min.
- Signaux qui n'ont pas bougé : ...
- Transactions traitées par la révision `next` avant la détection : ... ; ce qu'elle en aurait traité à 100 % : ...

## 3. Cause

- Ce qui a changé entre la révision `candidate` et la révision `next` : ...
- Comment ce changement produit le signal observé : ...
- Observation qui l'établit (extrait de log, courbe) :

```text
...
```

## 4. Action qui aurait détecté plus tôt

| Action | Ce qu'elle aurait vu | Quand (étape de la livraison) | Délai gagné | Responsable |
| --- | --- | --- | --- | --- |
| ... | ... | ... | ... | ... |
