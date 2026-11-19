# Infrastructure de l'équipe — Advanced Cloud AI Infrastructure

Ce dépôt contient l'infrastructure de votre équipe, écrite en Terraform. Il vous suit pendant tout le
cours : chaque séance y ajoute des ressources. Vous travaillez sur un **fork** par équipe.

Toutes les équipes partagent un seul projet Google Cloud, `advanced-cloud-ai`, région `europe-west1`.

| Qui | Gère | Vos droits |
| --- | --- | --- |
| Enseignant (socle) | APIs, bucket des states, registre d'images `cloud-ai`, bucket des modèles | lecture seule |
| Votre équipe (tranche) | compte de service d'exécution, service Cloud Run, règles d'accès | création et suppression |

## Trois règles dans le projet partagé

1. Chaque nom de ressource commence par votre identifiant d'équipe : `team1-fraud-api`.
2. Chaque ressource porte le label `team` (posé automatiquement par le provider, voir `infra/versions.tf`).
3. Votre state Terraform vit sous votre préfixe, dans le bucket partagé `advanced-cloud-ai-tfstate`.

Les droits ne vous empêchent pas de modifier un service Cloud Run d'une autre équipe : seul le nommage
vous en protège. Vérifiez le nom avant chaque suppression.

## Contenu

| Chemin | Rôle |
| --- | --- |
| `infra/` | votre Terraform : `backend.tf`, `variables.tf`, `main.tf`, `outputs.tf` |
| `docs/seance-2.md` | énoncé de la séance 2 : déployer le service de scoring sur Cloud Run |
| `docs/seance-3.md` | énoncé de la séance 3 : brancher le service sur un flux Pub/Sub |
| `docs/seance-3/` | squelette `pubsub.tf`, exemple d'enveloppe push, modèle de compte rendu |
| `docs/seance-5.md` | énoncé de la séance 5 : réentraîner le scorer en job, recherche parallèle, règle d'entrée au registre |
| `docs/seance-5/` | squelette `job.tf`, script `custom-job.sh` (Vertex AI), modèle de compte rendu |
| `docs/seance-6.md` | énoncé de la séance 6 : livrer le challenger par paliers, diagnostiquer une panne, revenir en arrière |
| `docs/seance-6/` | scripts de livraison (`release.sh`, `shadow.sh`, `validate.sh`, `promote.sh`, `lib.sh`), mesure par révision (`measure.py`), workflow `release.yml`, modèles de `mesures.md`, `post-mortem.md` et `checklist.md` |

## Outils à installer

Il faut `gcloud`, `terraform` (≥ 1.9) et Docker. Toutes les commandes du cours sont des commandes
bash.

**macOS** : dans le Terminal.

```bash
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
```

`gcloud` : <https://cloud.google.com/sdk/docs/install>. Docker : celui du TD 1.

**Windows** : tout se fait dans le terminal **Ubuntu (WSL 2)** installé pour le TD 1, jamais dans
PowerShell. `gcloud` et `terraform` s'installent donc dans Ubuntu, pas dans Windows :

```bash
sudo apt-get update && sudo apt-get install -y gnupg curl lsb-release

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

sudo apt-get update && sudo apt-get install -y terraform google-cloud-cli
```

Clonez le dépôt dans votre dossier Linux (`cd ~`), pas dans `/mnt/c/...`.

**Les deux systèmes** : vérifier, puis se connecter.

```bash
terraform version && gcloud version && docker version

gcloud auth login
gcloud auth application-default login
gcloud config set project advanced-cloud-ai
gcloud auth configure-docker europe-west1-docker.pkg.dev
```

Sous Windows, si le navigateur ne s'ouvre pas, ajoutez `--no-launch-browser` aux deux commandes
`gcloud auth` : gcloud affiche un lien à ouvrir à la main et attend le code en retour.
