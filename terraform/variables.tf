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
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username for all VMs"
  default     = "kalyan2212"
}

variable "ssh_public_key" {
  description = "SSH public key content for VM authentication"
  # Default is a pre-generated key; deploy-all.yml overrides with a fresh key each run.
  # Private key for the default: base64-decode LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNBZXM2ZmZYS3ZuTFBaNThpY2lYL3d4QzVlUUhIams1RmFjVVRrZTYzejZUZ0FBQUtBWWxiaXdHSlc0CnNBQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQWVzNmZmWEt2bkxQWjU4aWNpWC93eEM1ZVFISGpLNUZhY1VUa2U2M3o2VGcKQUFBRUE0WmRkN09CbEp3ODZyRXJTSFhiNzliY2ZXVzMzQXh4cEZubjI1MWhoS09CNnpwOTljcStjczlubnlKeUpmL0RFTApsNUFjZU1ya1ZweFJPUjdyZlBwT0FBQUFHbVJ2ZDI1emRISmxZVzB0WVhCd0xXUmxjR3h2ZVMweU1ESTBBUUlECi0tLS0tRU5EIE9QRU5TU0ggUFJJVkFURSBLRVktLS0tLQo=
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6zp99cq+cs9nnyJyJf/DELl5AceMrkVpxROR7rfPpO downstream-app-deploy-2024"
}

variable "db_name"     { default = "downstream" }
variable "db_user"     { default = "downstream_user" }
variable "db_password" {
  description = "PostgreSQL downstream user password"
  sensitive   = true
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
