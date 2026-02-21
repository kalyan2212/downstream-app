variable "location" {
  description = "Azure region"
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  default     = "downstream-rg"
}

variable "vnet_address_space" { default = "10.0.0.0/16" }
variable "app_subnet_prefix"  { default = "10.0.1.0/24" }
variable "db_subnet_prefix"   { default = "10.0.2.0/24" }

variable "vm_size" {
  description = "Azure VM size"
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Admin username for all VMs"
  default     = "kalyan2212"
}

variable "db_name"     { default = "downstream" }
variable "db_user"     { default = "downstream_user" }
variable "db_password" {
  description = "PostgreSQL downstream user password"
  sensitive   = true
}

variable "replication_password" {
  description = "PostgreSQL replication user password"
  sensitive   = true
  default     = ""
}

variable "flask_secret" {
  description = "Flask secret key"
  sensitive   = true
  default     = "change-me-in-production"
}

variable "upstream_url" {
  description = "Base URL for the upstream API"
  default     = "http://localhost:5000"
}

variable "upstream_api_key" {
  description = "API key for the upstream API"
  default     = "downstream-app-key-002"
}

variable "github_repo_url" {
  description = "HTTPS clone URL of the GitHub repo"
  default     = "https://github.com/kalyan2212/downstream-app.git"
}

variable "availability_zone" {
  description = "Azure Availability Zone"
  default     = "1"
}
