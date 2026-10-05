# Secrets générés par Terraform : aucun mot de passe écrit à la main
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "random_password" "grafana" {
  length  = 16
  special = false
}

locals {
  site_domain  = azurerm_public_ip.app.fqdn
  site_address = var.enable_https ? local.site_domain : ":80"
}

resource "azurerm_linux_virtual_machine" "app" {
  name                            = "vm-${var.app_name}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app.id]
  tags                            = local.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.public_key_path))
  }

  os_disk {
    name                 = "osdisk-${var.app_name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Identité managée : la VM accède au stockage sans aucune clé
  identity {
    type = "SystemAssigned"
  }

  # Exécuté au premier démarrage (cloud-init)
  custom_data = base64encode(templatefile("${path.module}/cloud-init.sh.tftpl", {
    repo_url         = var.repo_url
    db_password      = random_password.db.result
    api_key          = random_password.api_key.result
    grafana_password = random_password.grafana.result
    site_address     = local.site_address
    storage_account  = azurerm_storage_account.backups.name
  }))
}
