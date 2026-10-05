resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  tags = {
    projet    = var.app_name
    gere-par  = "terraform"
    formation = "esatic-cloud"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.app_name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- Réseau isolé dédié au projet
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.app_name}"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.20.1.0/24"]
}

# ---------------------------------------------------------------- Pare-feu (Network Security Group)
resource "azurerm_network_security_group" "web" {
  name                = "nsg-${var.app_name}-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  security_rule {
    name                       = "allow-http-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh-admin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.web.id
}

# IP publique fixe avec un nom DNS Azure (sert au certificat HTTPS)
resource "azurerm_public_ip" "app" {
  name                = "pip-${var.app_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "${var.app_name}-${random_string.suffix.result}"
  tags                = local.tags
}

resource "azurerm_network_interface" "app" {
  name                = "nic-${var.app_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app.id
  }
}
