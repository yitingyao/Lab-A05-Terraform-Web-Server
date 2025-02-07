###################################################
#  Variables
###################################################
variable "labelPrefix" {
  type    = string
  default = "yao00043"
}

variable "region" {
  type    = string
  default = "eastus"
}

variable "admin_username" {
  type    = string
  default = "azureadmin"
}

###################################################
#  Configure Terraform runtime + providers
###################################################
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "cloudinit" {
  # No special config needed
}

###################################################
#  Resource Group
###################################################
resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

###################################################
#  Public IP
###################################################
resource "azurerm_public_ip" "public_ip" {
  name                = "${var.labelPrefix}-publicip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

###################################################
#  Virtual Network
###################################################
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.labelPrefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

###################################################
#  Subnet
###################################################
resource "azurerm_subnet" "subnet" {
  name                 = "${var.labelPrefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

###################################################
#  Network Security Group (NSG)
###################################################
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.labelPrefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow SSH (port 22)
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP (port 80)
  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

###################################################
#  Network Interface (NIC)
###################################################
resource "azurerm_network_interface" "nic" {
  name                = "${var.labelPrefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${var.labelPrefix}-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

###################################################
#  Associate NSG with the NIC
###################################################
resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
###################################################
#  Cloud-Init data (for installing Apache)
###################################################
data "cloudinit_config" "apache_config" {
  gzip          = false
  # This is the critical change:
  base64_encode = true

  part {
    filename     = "apache-install.sh"
    content_type = "text/x-shellscript"
    content      = file("${path.module}/init.sh")
  }
}

###################################################
#  Azure Linux VM
###################################################
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.labelPrefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  # Required: Add an os_disk block
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("C:\\Users\\Yitin\\.ssh\\id_rsa.pub")
  }

  # Use the base64-encoded data
  custom_data = data.cloudinit_config.apache_config.rendered

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}


###################################################
#  Outputs
###################################################
output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  description = "The Public IP address of the VM."
  value       = azurerm_public_ip.public_ip.ip_address
}
