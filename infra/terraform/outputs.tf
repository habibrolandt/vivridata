output "public_ip" {
  description = "IP publique fixe de la VM"
  value       = azurerm_public_ip.app.ip_address
}

output "app_url" {
  description = "Adresse de l'application (prête environ 5 minutes après l'apply)"
  value       = var.enable_https ? "https://${local.site_domain}" : "http://${local.site_domain}"
}

output "grafana_url" {
  description = "Tableau de bord de supervision"
  value       = var.enable_https ? "https://${local.site_domain}/grafana/" : "http://${local.site_domain}/grafana/"
}

output "ssh_command" {
  description = "Connexion SSH à la VM"
  value       = "ssh -i ${trimsuffix(var.public_key_path, ".pub")} azureuser@${local.site_domain}"
}

output "backup_storage_account" {
  description = "Compte de stockage des sauvegardes"
  value       = azurerm_storage_account.backups.name
}

output "resource_group" {
  description = "Groupe de ressources (tout le projet est dedans)"
  value       = azurerm_resource_group.main.name
}

output "github_variables" {
  description = "Variables à créer dans GitHub (Settings > Secrets and variables > Actions > Variables)"
  value = local.enable_cicd ? {
    AZURE_CLIENT_ID       = azurerm_user_assigned_identity.github_deploy[0].client_id
    AZURE_TENANT_ID       = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID = var.subscription_id
    AZURE_RESOURCE_GROUP  = azurerm_resource_group.main.name
    AZURE_VM_NAME         = azurerm_linux_virtual_machine.app.name
  } : null
}

output "api_key" {
  description = "Clé API des agents de collecte (terraform output -raw api_key)"
  value       = random_password.api_key.result
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Mot de passe admin Grafana (terraform output -raw grafana_admin_password)"
  value       = random_password.grafana.result
  sensitive   = true
}
