variable "vm_count" {
    type = string
    description = "Number of total Virtual Machines to deploy"
    default     = 1
}

variable "rgname" {
    type = string
    description = "Resource Group Name"
    default     = "resource-group"
}

variable "location" {
    type = string
    description = "Location of RG and Resources"
    default     = "eastus"
}

variable "vmsize" {
    type = string
    description = "VM Size"
    default     = "Standard_D2s_v3"
}

variable "user" {
    type = string
    description = "Admin User"
    default = "azureuser"
}

variable "subnetsetting1" {}

variable "subnetsetting2" {}

variable "security_rule_var" {}