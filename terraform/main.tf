# Downstream App - Azure Infrastructure
# All resources in Availability Zone 1, East US
#
# Topology:
#   Internet --> Azure Load Balancer (Standard, public IP)
#     Port 80   --> App VM 0 :80
#     Port 80   --> App VM 1 :80
#     Port 2201 --> App VM 0 :22  (SSH NAT)
#     Port 2202 --> App VM 1 :22  (SSH NAT)
#
#   App Subnet 10.0.1.0/24
#     App VM 0  (nginx + gunicorn + flask)
#     App VM 1  (nginx + gunicorn + flask)
#
#   DB Subnet 10.0.2.0/24
#     DB Primary  10.0.2.4  (PostgreSQL 15, primary)
#     DB Replica  10.0.2.5  (PostgreSQL 15, hot standby)

locals {
  db_primary_ip    = "10.0.2.4"
  db_replica_ip    = "10.0.2.5"
  ubuntu_publisher = "Canonical"
  ubuntu_offer     = "0001-com-ubuntu-server-jammy"
  ubuntu_sku       = "22_04-lts-gen2"
  ubuntu_version   = "latest"
  tags = {
    project     = "downstream-app"
    environment = "production"
    managed_by  = "terraform"
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Generate an RSA 4096-bit key pair for VM SSH access.
# Azure only supports RSA keys; this avoids errors if the user has an ed25519 key.
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "downstream-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_subnet" "app_subnet" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.app_subnet_prefix]
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.db_subnet_prefix]
}

resource "azurerm_network_security_group" "app_nsg" {
  name                = "app-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-ssh"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "db_nsg" {
  name                = "db-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  security_rule {
    name                       = "allow-postgres-from-app"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.app_subnet_prefix
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-postgres-replication"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.db_subnet_prefix
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-ssh"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app_nsg_assoc" {
  subnet_id                 = azurerm_subnet.app_subnet.id
  network_security_group_id = azurerm_network_security_group.app_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "db_nsg_assoc" {
  subnet_id                 = azurerm_subnet.db_subnet.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

resource "azurerm_public_ip" "lb_pip" {
  name                = "downstream-lb-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.availability_zone]
  tags                = local.tags
}

resource "azurerm_lb" "app_lb" {
  name                = "downstream-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb_pip.id
    zones                = [var.availability_zone]
  }
}

resource "azurerm_lb_backend_address_pool" "app_pool" {
  name            = "app-backend-pool"
  loadbalancer_id = azurerm_lb.app_lb.id
}

resource "azurerm_lb_probe" "http_probe" {
  name                = "http-probe"
  loadbalancer_id     = azurerm_lb.app_lb.id
  protocol            = "Tcp"
  port                = 80
  interval_in_seconds = 5
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http_rule" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.app_lb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app_pool.id]
  probe_id                       = azurerm_lb_probe.http_probe.id
  disable_outbound_snat          = true
}

resource "azurerm_lb_outbound_rule" "app_outbound" {
  name                    = "app-outbound"
  loadbalancer_id         = azurerm_lb.app_lb.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app_pool.id
  frontend_ip_configuration { name = "frontend" }
}

resource "azurerm_lb_nat_rule" "ssh_nat" {
  count                          = 2
  name                           = "ssh-vm-${count.index}"
  resource_group_name            = azurerm_resource_group.rg.name
  loadbalancer_id                = azurerm_lb.app_lb.id
  protocol                       = "Tcp"
  frontend_port                  = 2201 + count.index
  backend_port                   = 22
  frontend_ip_configuration_name = "frontend"
}

resource "azurerm_network_interface" "app_nic" {
  count               = 2
  name                = "app-vm-${count.index}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "app_pool_assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.app_nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app_pool.id
}

resource "azurerm_network_interface_nat_rule_association" "app_ssh_nat_assoc" {
  count                 = 2
  network_interface_id  = azurerm_network_interface.app_nic[count.index].id
  ip_configuration_name = "internal"
  nat_rule_id           = azurerm_lb_nat_rule.ssh_nat[count.index].id
}

resource "azurerm_network_interface" "db_primary_nic" {
  name                = "db-primary-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.db_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.db_primary_ip
  }
}

resource "azurerm_network_interface" "db_replica_nic" {
  name                = "db-replica-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.db_subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.db_replica_ip
  }
}

resource "azurerm_linux_virtual_machine" "app_vm" {
  count               = 2
  name                = "app-vm-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username
  zone                = var.availability_zone
  tags                = local.tags

  network_interface_ids = [azurerm_network_interface.app_nic[count.index].id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = local.ubuntu_publisher
    offer     = local.ubuntu_offer
    sku       = local.ubuntu_sku
    version   = local.ubuntu_version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-app.sh.tpl", {
    db_host        = local.db_primary_ip
    db_name        = var.db_name
    db_user        = var.db_user
    db_password    = var.db_password
    flask_secret   = var.flask_secret
    upstream_url   = var.upstream_url
    api_key        = var.upstream_api_key
    github_repo    = var.github_repo_url
    admin_username = var.admin_username
  }))

  depends_on = [
    azurerm_network_interface_backend_address_pool_association.app_pool_assoc,
    azurerm_network_interface_nat_rule_association.app_ssh_nat_assoc,
  ]
}

resource "azurerm_linux_virtual_machine" "db_primary" {
  name                = "db-primary"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username
  zone                = var.availability_zone
  tags                = local.tags

  network_interface_ids = [azurerm_network_interface.db_primary_nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = local.ubuntu_publisher
    offer     = local.ubuntu_offer
    sku       = local.ubuntu_sku
    version   = local.ubuntu_version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-db-primary.sh.tpl", {
    db_name              = var.db_name
    db_user              = var.db_user
    db_password          = var.db_password
    replication_password = var.replication_password
    replica_ip           = local.db_replica_ip
    app_subnet           = var.app_subnet_prefix
  }))
}

resource "azurerm_linux_virtual_machine" "db_replica" {
  name                = "db-replica"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username
  zone                = var.availability_zone
  tags                = local.tags

  network_interface_ids = [azurerm_network_interface.db_replica_nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = local.ubuntu_publisher
    offer     = local.ubuntu_offer
    sku       = local.ubuntu_sku
    version   = local.ubuntu_version
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-db-replica.sh.tpl", {
    primary_ip           = local.db_primary_ip
    replication_password = var.replication_password
  }))

  depends_on = [azurerm_linux_virtual_machine.db_primary]
}
