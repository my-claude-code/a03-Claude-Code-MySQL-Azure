terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  prefix          = "flask-notes"
  mysql_private_ip = "10.0.1.10"
  app_private_ip   = "10.0.1.20"
}

# ── Resource Group ───────────────────────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.prefix}"
  location = var.location
}

# ── Virtual Network & Subnet ─────────────────────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${local.prefix}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ── NSG — allow all inbound (testing only) ───────────────────────────────────
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${local.prefix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-all-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ── Public IPs (static so we know the address before VM creation) ────────────
resource "azurerm_public_ip" "mysql" {
  name                = "pip-mysql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "app" {
  name                = "pip-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ── Network Interfaces ───────────────────────────────────────────────────────
resource "azurerm_network_interface" "mysql" {
  name                = "nic-mysql"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig-mysql"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.mysql_private_ip
    public_ip_address_id          = azurerm_public_ip.mysql.id
  }
}

resource "azurerm_network_interface" "app" {
  name                = "nic-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig-app"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.app_private_ip
    public_ip_address_id          = azurerm_public_ip.app.id
  }
}

# ── NSG ↔ NIC associations ───────────────────────────────────────────────────
resource "azurerm_network_interface_security_group_association" "mysql" {
  network_interface_id      = azurerm_network_interface.mysql.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface_security_group_association" "app" {
  network_interface_id      = azurerm_network_interface.app.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ── MySQL VM ─────────────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "mysql" {
  name                            = "vm-mysql"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.mysql.id]

  custom_data = base64encode(templatefile("${path.module}/scripts/mysql-setup.sh", {
    db_name     = "flask_notes"
    db_user     = "flask_user"
    db_password = var.db_password
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# ── App VM ───────────────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "app" {
  name                            = "vm-app"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.app.id]

  custom_data = base64encode(templatefile("${path.module}/scripts/app-setup.sh", {
    entra_client_id     = var.entra_client_id
    entra_client_secret = var.entra_client_secret
    entra_tenant_id     = var.entra_tenant_id
    flask_secret_key    = var.flask_secret_key
    app_public_ip       = azurerm_public_ip.app.ip_address
    mysql_private_ip    = local.mysql_private_ip
    db_name             = "flask_notes"
    db_user             = "flask_user"
    db_password         = var.db_password
  }))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Ensures the MySQL VM resource exists before the app VM is created.
  # The app setup script additionally waits for MySQL to be fully ready.
  depends_on = [azurerm_linux_virtual_machine.mysql]
}
