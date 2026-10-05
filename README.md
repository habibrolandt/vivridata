# VivriData CI — Observatoire cloud des prix des produits vivriers

Plateforme qui centralise les prix relevés sur les marchés ivoiriens (Adjamé, Bouaké, Daloa…)
et les rend consultables en temps réel : tableau de bord, API ouverte, export CSV.
Toute l'infrastructure est déployée sur **Microsoft Azure** et décrite en code (**Terraform**).

> Les historiques de prix fournis au démarrage sont **simulés** pour la démonstration.
> Les relevés saisis via l'API ou le formulaire sont réels et persistés.

---

## 1. Cadrage

**Contexte.** La vie chère est un sujet majeur en Côte d'Ivoire. Les prix du riz, de la tomate ou de
l'attiéké varient fortement d'un marché à l'autre et d'une semaine à l'autre, mais l'information
circule mal : relevés sur papier, fichiers Excel isolés, publication tardive.

**Problème.** Un organisme de suivi des prix (ministère, ONG, coopérative) a besoin d'une plateforme
qui collecte les relevés de dizaines d'agents, les rend disponibles immédiatement, résiste aux pannes,
supporte les pics de consultation et ne demande pas d'acheter ni d'administrer des serveurs.

**Solution.** Une application conteneurisée hébergée sur Azure, dont l'infrastructure complète
(réseau, pare-feu, serveur, stockage, identités) est créée par une seule commande `terraform apply`.

**Objectifs et preuves en direct**

| # | Objectif | Indicateur | Preuve en démo |
|---|----------|-----------|----------------|
| 1 | Infrastructure as Code | 100 % de l'infra créée par Terraform | `terraform apply`, puis le portail Azure |
| 2 | Accès public sécurisé | HTTPS avec certificat valide | cadenas dans le navigateur |
| 3 | Haute disponibilité | 2 instances minimum, reprise automatique | `demo.sh crash` : le service continue |
| 4 | Scalabilité horizontale | 2 → 4 instances sans interruption | `demo.sh scale`, Grafana |
| 5 | Observabilité | trafic, latence, erreurs, CPU, RAM | tableau de bord Grafana en direct |
| 6 | Durabilité des données | volume persistant + sauvegarde Blob Storage | `demo.sh persist`, `demo.sh backup` |
| 7 | Sécurité | moindre privilège, identité managée, aucun secret dans le code | NSG, rôles RBAC |
| 8 | Livraison continue | push → tests → build → déploiement | onglet Actions de GitHub, version affichée |

**Modèle cloud.** IaaS (Azure Virtual Machines) complété par des services managés (Blob Storage,
identités managées, Run Command), sur cloud public, région `francecentral` (Paris).

**Hors périmètre (perspectives).** VM Scale Set multi-zones derrière Azure Load Balancer ou
Application Gateway, Azure Database for PostgreSQL, Azure Container Apps ou AKS, alertes Azure Monitor.

---

## 2. Architecture

```
                         Utilisateurs (navigateur, agents de collecte)
                                        │ HTTPS 443  (vivridata-xxxxxx.francecentral.cloudapp.azure.com)
 ┌────────────────────────── Microsoft Azure · France Central ────────────────────────┐
 │  Groupe de ressources rg-vivridata · VNet 10.20.0.0/16 · sous-réseau 10.20.1.0/24   │
 │  NSG : 80/443 publics ; 22 limité à l'IP de l'administrateur                        │
 │                                                                                    │
 │  ┌──── VM Standard_B2s · Ubuntu 24.04 · IP statique + nom DNS · identité managée ┐  │
 │  │                                                                              │  │
 │  │   Caddy ──► app #1 ─┐                     Prometheus ◄── node-exporter       │  │
 │  │ (HTTPS + LB) app #2 ─┼──► PostgreSQL           │                             │  │
 │  │          ──► app #n ─┘    (volume)          Grafana (/grafana)              │  │
 │  │                              │                                              │  │
 │  └──────────────────────────────┼──────────────────────────────────────────────┘  │
 │                                 │ pg_dump (identité managée, sans clé)              │
 │                 Blob Storage : sauvegardes privées, versionnées, supprimées à 30 j  │
 └────────────────────────────────────────────────────────────────────────────────────┘
   GitHub ── push ──► Actions : tests → build → (OIDC) → Run Command → mise à jour de la VM
```

| Couche | Technologie | Notion cloud |
|--------|-------------|--------------|
| Provisionnement | Terraform | Infrastructure as Code, reproductibilité |
| Organisation | Groupe de ressources, étiquettes | gouvernance, suppression en un geste |
| Réseau | VNet, sous-réseau, NSG | isolation, filtrage |
| Calcul | Azure VM Standard_B2s, IP statique + DNS | IaaS, élasticité, paiement à l'usage |
| Entrée | Caddy | reverse proxy, HTTPS automatique, répartition de charge |
| Application | FastAPI conteneurisé (Docker) | portabilité, scalabilité horizontale |
| Données | PostgreSQL + volume Docker | persistance, séparation état / calcul |
| Sauvegarde | Azure Blob Storage | stockage objet, durabilité, cycle de vie |
| Identité | Identité managée, RBAC, fédération OIDC | moindre privilège, zéro clé longue durée |
| Observabilité | Prometheus, Grafana, node-exporter | supervision, métriques |
| Livraison | GitHub Actions + Run Command | CI/CD, DevOps |

---

## 3. Déploiement depuis un Mac (≈ 40 min)

### 3.1 Outils et connexion (10 min)
```bash
brew install git azure-cli
brew tap hashicorp/tap && brew install hashicorp/tap/terraform

az login                                              # compte @esatic.edu.ci
az account show --query "{nom:name, id:id}" -o table  # note l'id de l'abonnement
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vivridata_rsa -N ""
curl ifconfig.me                                      # note ton IP publique
```

### 3.2 Publier le code sur GitHub (5 min)
Crée un dépôt **public et vide** nommé `vivridata`, puis dans le dossier du projet :
```bash
git init && git add . && git commit -m "VivriData CI v1"
git branch -M main
git remote add origin https://github.com/TON_USER/vivridata.git
git push -u origin main
```
Si Git demande un mot de passe : utilise un *Personal access token* GitHub
(Settings → Developer settings → Personal access tokens, droit `repo`).

### 3.3 Créer l'infrastructure (5 min de commande + 5 min d'installation automatique)
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
open -e terraform.tfvars        # subscription_id, ton IP + /32, TON_USER (2 fois) ; enregistrer
terraform init
terraform plan                  # montre les 19 ressources qui vont être créées
terraform apply                 # tape "yes"
```
Terraform affiche `app_url`, `grafana_url` et `ssh_command`.
**Attends 5 minutes** : la VM installe Docker et démarre tout. Puis ouvre `app_url`.

Secrets générés :
```bash
terraform output -raw api_key                  # clé pour saisir un relevé
terraform output -raw grafana_admin_password   # admin Grafana (la lecture est publique)
```

### 3.4 Se connecter à la VM
```bash
$(terraform output -raw ssh_command)
sudo -i
cd /opt/vivridata
bash deploy/demo.sh                      # liste des commandes de démo
```
**Si SSH est refusé (IP différente à l'école)** : autorise ta nouvelle IP en une commande, depuis
`infra/terraform` :
```bash
az network nsg rule update -g rg-vivridata --nsg-name nsg-vivridata-web -n allow-ssh-admin \
  --source-address-prefixes "$(curl -s ifconfig.me)/32"
```

### 3.5 Activer le CI/CD (5 min, facultatif)
```bash
terraform output github_variables
```
Crée chacune de ces 5 variables dans GitHub : *Settings → Secrets and variables → Actions → Variables*.
Aucun secret à stocker : GitHub obtient un jeton temporaire par fédération d'identité.
Test : modifie un texte de `app/static/index.html`, `git push`, regarde l'onglet *Actions* ;
la version affichée en haut à droite de l'application prend le nouveau numéro de commit.

### 3.6 Après la présentation
```bash
terraform destroy      # supprime tout le groupe de ressources : plus aucun coût
```

---

## 4. Scénario de démonstration (≈ 10 min)

Prépare 4 fenêtres : l'application, Grafana (`/grafana/`), le portail Azure (groupe `rg-vivridata`),
et un Terminal connecté à la VM (`sudo -i`, `cd /opt/vivridata`).

| # | Ce que tu montres | Commande / action |
|---|-------------------|-------------------|
| 1 | L'infra est du code | `infra/terraform/*.tf`, puis le portail : groupe `rg-vivridata` et ses ressources |
| 2 | Application en HTTPS | ouvrir `app_url`, cadenas, tableau de bord, choisir « Tomate » |
| 3 | Un agent saisit un prix | formulaire + clé API (`bash deploy/demo.sh secrets`) ; KPI et tableau se mettent à jour |
| 4 | Répartition de charge | `bash deploy/demo.sh lb` : deux instances différentes répondent |
| 5 | Pic de trafic + supervision | `bash deploy/demo.sh load` pendant que Grafana montre les requêtes/s monter |
| 6 | Scalabilité | `bash deploy/demo.sh scale` → 4 instances ; Grafana « Instances API actives » passe à 4 |
| 7 | Panne d'une instance | `bash deploy/demo.sh crash` : HTTP 200 continus, redémarrage automatique |
| 8 | Persistance | `bash deploy/demo.sh persist` puis rafraîchir : le relevé saisi est toujours là |
| 9 | Sauvegarde | `bash deploy/demo.sh backup` puis `backups`, et le fichier dans le portail (compte de stockage → conteneur `backups`) |
| 10 | CI/CD | `git push` d'une modification, onglet Actions, nouvelle version affichée |

**Ce soir : répète toute la démo une fois et fais des captures d'écran** (Cmd + Shift + 4),
plan de secours si le réseau de la salle est mauvais.

---

## 5. Questions probables

- **Pourquoi pas tout en services managés (Azure Database, Container Apps) ?** Choix assumé coût /
  pédagogie : une VM montre chaque couche. En production : Azure Database for PostgreSQL et Container Apps ou AKS.
- **Que se passe-t-il si la VM tombe ?** Limite principale (une seule zone). Les données restent
  sauvegardées sur Blob Storage et `terraform apply` recrée l'infrastructure. Étape suivante :
  VM Scale Set sur plusieurs zones derrière un Load Balancer.
- **Pourquoi Caddy et pas Nginx ?** HTTPS Let's Encrypt automatique et découverte dynamique des
  répliques : on scale sans redémarrer le proxy.
- **Comment la VM écrit dans le stockage sans clé ?** Identité managée attribuée à la VM, avec le rôle
  « Storage Blob Data Contributor » sur ce seul conteneur ; jeton temporaire fourni par le service
  de métadonnées Azure.
- **Comment GitHub déploie sans secret ?** Fédération d'identité OIDC : GitHub prouve son identité
  à Microsoft Entra ID, qui délivre un jeton temporaire uniquement pour la branche `main` de ce dépôt,
  limité à la commande à distance sur cette VM.
- **D'où vient le nom de domaine ?** Azure attribue un nom DNS à l'IP publique
  (`…cloudapp.azure.com`), ce qui permet un vrai certificat HTTPS sans acheter de domaine.
- **Coût ?** Une B2s coûte quelques centimes de dollar par heure, couverts par les 200 $ de crédits
  Azure for Students. `terraform destroy` supprime tout le groupe de ressources.
- **Pourquoi Paris et pas l'Afrique ?** `southafricanorth` (Johannesburg) se choisit en changeant
  la variable `location` ; Paris offre une bonne latence vers Abidjan.

---

## 6. Dépannage

| Symptôme | Solution |
|----------|----------|
| `RequestDisallowedByAzure` ou région refusée | l'abonnement étudiant limite les régions : le message liste celles autorisées, mettre l'une d'elles dans `location` |
| Taille de VM indisponible (`SkuNotAvailable`) | `vm_size = "Standard_B2ms"` ou une autre région |
| Page inaccessible juste après `apply` | attendre 5 min ; sur la VM : `sudo tail -f /var/log/vivridata-bootstrap.log` |
| Erreur de certificat HTTPS | sur la VM : `sed -i 's/^SITE_ADDRESS=.*/SITE_ADDRESS=:80/' .env && bash deploy/update.sh` puis `http://…` |
| SSH refusé | voir la commande `az network nsg rule update` en 3.4 |
| `backup` refusé (403) juste après le déploiement | le rôle RBAC met quelques minutes à s'appliquer : réessayer |

**Plan B sans Terraform** : créer à la main une VM Ubuntu 24.04 B2s dans le portail (ports 22, 80, 443
autorisés), puis en SSH : `sudo git clone <dépôt> /opt/vivridata && sudo bash /opt/vivridata/deploy/bootstrap.sh`.
Tout fonctionne sauf la sauvegarde vers Blob Storage et le CI/CD.

---

## 7. Lancer en local sur Mac

Sans Docker (pour voir l'application) — **Python 3.12 obligatoire** :
```bash
brew install python@3.12
/opt/homebrew/bin/python3.12 -m venv venv && source venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --reload        # http://localhost:8000
```

Avec Docker Desktop (pile complète, sauf node-exporter qui a besoin d'un vrai Linux) :
```bash
cp .env.example .env
docker compose up -d --build caddy app db prometheus grafana
# http://localhost  et  http://localhost/grafana/
```
