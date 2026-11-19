# Checklist de préparation opérationnelle — team1

Une ligne sans preuve est un non. Un non est une réponse recevable : écrivez alors ce qui manque.

| Ligne | Question | Oui / non | Preuve | Ce qui manque |
| --- | --- | --- | --- | --- |
| Validated | Le modèle a-t-il été validé avant de recevoir du trafic, sur des segments et en ombre ? | ... | verdict de `validation.txt`, segment le plus faible, désaccord et écart d'alertes en ombre : ... | ... |
| Reversible | Peut-on revenir en arrière par une commande écrite d'avance, et l'a-t-on vérifié par la mesure ? | ... | critères horodatés, tableau des paliers, ligne « retour » de `mesures.md` : ... | ... |
| Observed | Voit-on, par révision, les signaux qui disent que le service va mal ? | ... | référence de l'étape 0, objectif de service, signal qui a détecté la panne : ... | ... |
| Degradable | Sait-on ce que fait le service quand la lecture de ses features échoue, et l'a-t-on choisi ? | ... | repli observé (`dégradés`, `alertes`) et politique retenue, ou ce qui manque pour en décider : ... | ... |
| Restorable | Peut-on reconstruire le service à l'identique (modèle, agrégats, configuration) ? | ... | `plan.txt` et les fichiers Terraform (`infra/release.tf`, `infra/scorer/`) : ... | ... |
| Owned | Chaque élément a-t-il un responsable et une politique de réentraînement ? | ... | politique retenue et un responsable par ligne : ... | ... |
