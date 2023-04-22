terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "3.44.1"
        }
    }
    backend "azurerm" {
        resource_group_name     = "azure-devops"
        storage_account_name    = "azuredevopsmsm"
        container_name          = "terraform"
        Key                     = "terraform.tfstate"
    }
}

provider "azurerm" {
    features{}
}

### DATA SOURCES ###

#Get existing Key Vault
data "azurerm_key_vault" "keyvault" {
    name                = "msm-keyvault"
    resource_group_name = "key-vault"
}

#Get existing Key
data "azurerm_key_vault_key" "ssh_key" {
    name         = "sshkey"
    key_vault_id = data.azurerm_key_vault.keyvault.id
}

### RESOURCES ###

#Replace user in YAML file
resource "null_resource" "replaceuser" {
    provisioner "local-exec" {
        command = format("cp base-cloud-init.yaml cloud-init.yaml && sed -i -e 's/#user#/%s/g' cloud-init.yaml",var.user)
    }
}

#Generate ramdom string
resource "random_string" "random" {
    length           = 14
    special          = false
}

#Resource Group
resource "azurerm_resource_group" "rg" {
    name        = var.rgname
    location    = var.location
}

#Network -> Create Virtual networks
resource "azurerm_virtual_network" "vnetgenerator1" {
    name                = format("%s-vnet1",var.rgname)
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    address_space       = ["192.168.1.0/24"]
    dns_servers         = ["8.8.8.8", "8.8.4.4"]
    dynamic "subnet" {
        for_each = var.subnetsetting1
        content {
            name           = subnet.value["name"]
            address_prefix = subnet.value["address_prefix"]
            security_group = subnet.value["security_group"]
        }
    }
}

resource "azurerm_virtual_network" "vnetgenerator2" {
    name                = format("%s-vnet2",var.rgname)
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    address_space       = ["192.168.2.0/24"]
    dns_servers         = ["8.8.8.8", "8.8.4.4"]
    dynamic "subnet" {
        for_each = var.subnetsetting2
        content {
            name           = subnet.value["name"]
            address_prefix = subnet.value["address_prefix"]
        }
    }
}

#Network -> Create NSG
resource "azurerm_network_security_group" "nsg1" {
    name                = "nsg1"
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    dynamic "security_rule" {
        for_each = var.security_rule_var
        content {
            name                       = security_rule.value["name"]
            priority                   = security_rule.value["priority"]
            direction                  = security_rule.value["direction"]
            access                     = security_rule.value["access"]
            protocol                   = security_rule.value["protocol"]
            source_port_range          = security_rule.value["source_port_range"]
            destination_port_range     = security_rule.value["destination_port_range"]
            source_address_prefix      = security_rule.value["source_address_prefix"]
            destination_address_prefix = security_rule.value["destination_address_prefix"]
        }
    }
}

#Network -> Peering 1 to 2
resource "azurerm_virtual_network_peering" "peer1" {
    name                      = "peer1to2"
    resource_group_name       = azurerm_resource_group.rg.name
    virtual_network_name      = azurerm_virtual_network.vnetgenerator1.name
    remote_virtual_network_id = azurerm_virtual_network.vnetgenerator2.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    allow_gateway_transit = false
}

#Network -> Peering 2 to 1
resource "azurerm_virtual_network_peering" "peer2" {
    name                      = "peer2to1"
    resource_group_name       = azurerm_resource_group.rg.name
    virtual_network_name      = azurerm_virtual_network.vnetgenerator2.name
    remote_virtual_network_id = azurerm_virtual_network.vnetgenerator1.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    allow_gateway_transit = false
}

#Network -> Create Public IP Address
resource "azurerm_public_ip" "publicip" {
    name                = format("%s-pip",var.rgname)
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
    allocation_method   = "Static"
    sku                 = "Standard"
    domain_name_label   = "tf-project-msm"
}

#Storage Account
resource "azurerm_storage_account" "storagea1" {
    name                        = lower(format("storageacc%s",random_string.random.result))
    resource_group_name         = azurerm_resource_group.rg.name
    location                    = azurerm_resource_group.rg.location
    account_tier                = "Standard"
    account_kind                = "StorageV2"
    account_replication_type    = "LRS"
    enable_https_traffic_only   = true
    depends_on = [
        random_string.random
    ]
}

#Monitoring -> Create Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "workspace" {
    name                = format("%s-nsgworkspace",var.rgname)
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    sku                 = "PerGB2018"
}

#Monitoring -> Create Network watcher flow log
resource "azurerm_network_watcher_flow_log" "flowlogs" {
    network_watcher_name = format("NetworkWatcher_%s", var.location)
    resource_group_name  = "NetworkWatcherRG"
    name                 = "nsgflow1"

    network_security_group_id = azurerm_network_security_group.nsg1.id
    storage_account_id        = azurerm_storage_account.storagea1.id
    enabled                   = true

    retention_policy {
        enabled = true
        days    = 7
    }

    traffic_analytics {
        enabled               = true
        workspace_id          = azurerm_log_analytics_workspace.workspace.workspace_id
        workspace_region      = azurerm_log_analytics_workspace.workspace.location
        workspace_resource_id = azurerm_log_analytics_workspace.workspace.id
        interval_in_minutes   = 10
    }
}

#Virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
    count                   = var.vm_count 
    name                    = format("%s-vm-%s",var.rgname,count.index + 1)
    resource_group_name     = azurerm_resource_group.rg.name
    location                = var.location
    size                    = var.vmsize
    admin_username          = var.user
    network_interface_ids   =   [ 
        azurerm_network_interface.nic[count.index].id
        ]
    custom_data             = filebase64("cloud-init.yaml")
    
    admin_ssh_key {
        username    = var.user
        public_key  = data.azurerm_key_vault_key.ssh_key.public_key_openssh
    }

    os_disk {
        caching                 = "ReadWrite"
        storage_account_type    = "Standard_LRS"
    }

    source_image_reference {
        publisher   = "Canonical"
        offer       = "0001-com-ubuntu-server-jammy"
        sku         = "22_04-lts-gen2"
        version     = "latest"
    }
    depends_on = [
        null_resource.replaceuser
    ]
}

#Virtual Machine -> Create NIC
resource "azurerm_network_interface" "nic" {
    count               = var.vm_count
    name                = format("%s-nic-%s",var.rgname,count.index + 1)
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
    ip_configuration {
        name                            = "internal"
        subnet_id                       = tolist(azurerm_virtual_network.vnetgenerator1.subnet)[0].id
        private_ip_address_allocation   = "Static"
        private_ip_address              = format("192.168.1.%s",count.index + 4)
    }
}

#Load Balancer
resource "azurerm_lb" "lb" {
    name                = format("%s-lb",var.rgname)
    location            = var.location
    resource_group_name = azurerm_resource_group.rg.name
    sku                 = "Standard"

    frontend_ip_configuration {
        name                 = "PublicIPAddress"
        public_ip_address_id = azurerm_public_ip.publicip.id
    }
}

#Load Balancer -> Create Backend Pool
resource "azurerm_lb_backend_address_pool" "lb-backend" {
    loadbalancer_id = azurerm_lb.lb.id
    name            = "BackendPool"
}

#Load Balancer -> Create Probe
resource "azurerm_lb_probe" "lb-probe" {
    loadbalancer_id = azurerm_lb.lb.id
    name            = "port-80-running"
    port            = "80"
}

#Load Balancer -> Create Rule
resource "azurerm_lb_rule" "lb-rule" {
    loadbalancer_id                 = azurerm_lb.lb.id
    backend_address_pool_ids        = [ azurerm_lb_backend_address_pool.lb-backend.id ]
    probe_id                        = azurerm_lb_probe.lb-probe.id
    name                            = "HTTP-Service"
    protocol                        = "Tcp"
    frontend_port                   = "80"
    backend_port                    = "80"
    frontend_ip_configuration_name  = azurerm_lb.lb.frontend_ip_configuration[0].name
}

#Load Balancer -> Backend - NIC Association
resource "azurerm_network_interface_backend_address_pool_association" "lb-nic" {
    count                   = var.vm_count
    network_interface_id    = azurerm_network_interface.nic[count.index].id
    ip_configuration_name   = azurerm_network_interface.nic[count.index].ip_configuration[0].name
    backend_address_pool_id = azurerm_lb_backend_address_pool.lb-backend.id
}

#Recovery Services Vault
resource "azurerm_recovery_services_vault" "vault1" {
    name                = format("%s-rsv",var.rgname)
    location            = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    sku                 = "Standard"
}

#Recovery Services Vault -> Backup Policy
resource "azurerm_backup_policy_vm" "police1" {
    name                = "Daily-Policy"
    resource_group_name = azurerm_resource_group.rg.name
    recovery_vault_name = azurerm_recovery_services_vault.vault1.name

    backup {
        frequency = "Daily"
        time      = "23:00"
    }

    retention_daily {
        count = 10
    }
}

#Recovery Services Vault -> Assign VM to backup
resource "azurerm_backup_protected_vm" "protected1" {
    count               = var.vm_count
    resource_group_name = azurerm_resource_group.rg.name
    recovery_vault_name = azurerm_recovery_services_vault.vault1.name
    source_vm_id        = azurerm_linux_virtual_machine.vm[count.index].id
    backup_policy_id    = azurerm_backup_policy_vm.police1.id
}