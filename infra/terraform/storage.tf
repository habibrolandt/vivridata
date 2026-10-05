# ---------------------------------------------------------------- Sauvegardes : Azure Blob Storage privé
resource "azurerm_storage_account" "backups" {
  name                            = "${var.app_name}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "backups" {
  name                  = "backups"
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# Suppression automatique des sauvegardes de plus de 30 jours
resource "azurerm_storage_management_policy" "backups" {
  storage_account_id = azurerm_storage_account.backups.id
  rule {
    name    = "expire-old-backups"
    enabled = true
    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["backups/"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
      version {
        delete_after_days_since_creation = 7
      }
    }
  }
}
