# ---------------------------------------------------------------- Droits de la VM : écrire dans SON conteneur uniquement
resource "azurerm_role_assignment" "vm_backups" {
  scope                = azurerm_storage_container.backups.resource_manager_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.app.identity[0].principal_id
}

# ---------------------------------------------------------------- CI/CD : GitHub Actions par fédération d'identité (OIDC)
locals {
  enable_cicd = var.github_repo != ""
}

data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "github_deploy" {
  count               = local.enable_cicd ? 1 : 0
  name                = "id-${var.app_name}-github-deploy"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

# Seule la branche main de CE dépôt peut obtenir un jeton
resource "azurerm_federated_identity_credential" "github_main" {
  count               = local.enable_cicd ? 1 : 0
  name                = "github-main"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.github_deploy[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repo}:ref:refs/heads/main"
}

# Moindre privilège : lancer une commande sur CETTE VM uniquement
resource "azurerm_role_assignment" "github_vm" {
  count                = local.enable_cicd ? 1 : 0
  scope                = azurerm_linux_virtual_machine.app.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_user_assigned_identity.github_deploy[0].principal_id
}
