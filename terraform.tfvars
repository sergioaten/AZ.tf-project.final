vm_count = 2

rgname = "TF-Project"

location = "northeurope"

vmsize = "Standard_B1s"

user = "azureuser"

subnetsetting1 = [
    {
      name           = "subnet1"
      address_prefix = "192.168.1.0/25"
      security_group = "/subscriptions/4cefcea5-7331-477c-a5d5-da6957ee15c7/resourceGroups/TF-Project/providers/Microsoft.Network/networkSecurityGroups/nsg1"
    },
    {
      name           = "subnet2"
      address_prefix = "192.168.1.128/25"
      security_group = null
    },
]
subnetsetting2 = [
    {
      name           = "subnet1"
      address_prefix = "192.168.2.0/25"
      security_group = null
    },
    {
      name           = "subnet2"
      address_prefix = "192.168.2.128/25"
      security_group = null
    },
]


security_rule_var = [
    {
    name                       = "ssh_allow"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "192.168.1.0/24"
    },
    {
    name                       = "http_allow"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "192.168.1.0/24"
    }
]