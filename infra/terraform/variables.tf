variable "subscription_id" {
  description = "Identifiant de l'abonnement Azure (az account show --query id -o tsv)"
  type        = string
}

variable "location" {
  description = "Région Azure (francecentral = Paris ; southafricanorth = Johannesburg)"
  type        = string
  default     = "francecentral"
}

variable "app_name" {
  description = "Nom de l'application, utilisé pour nommer et étiqueter les ressources"
  type        = string
  default     = "vivridata"
}

variable "vm_size" {
  description = "Taille de la VM (Standard_B2s = 2 vCPU, 4 Go de RAM)"
  type        = string
  default     = "Standard_B2s"
}

variable "allowed_ssh_cidr" {
  description = "Adresse IP autorisée en SSH, au format x.x.x.x/32 (ton IP publique)"
  type        = string
}

variable "public_key_path" {
  description = "Chemin de la clé publique SSH (RSA) installée sur la VM"
  type        = string
  default     = "~/.ssh/vivridata_rsa.pub"
}

variable "repo_url" {
  description = "URL HTTPS du dépôt GitHub public contenant le projet"
  type        = string
}

variable "enable_https" {
  description = "Active HTTPS automatique (Let's Encrypt) sur le nom DNS Azure de la VM"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "Dépôt GitHub au format utilisateur/depot autorisé à déployer (vide = pas de CI/CD)"
  type        = string
  default     = ""
}
