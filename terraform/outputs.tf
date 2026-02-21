output "app_public_ip" {
  description = "Public IP of the App VM"
  value       = azurerm_public_ip.app_pip.ip_address
}

output "app_url" {
  description = "Application URL"
  value       = "http://${azurerm_public_ip.app_pip.ip_address}"
}

output "ssh_app_vm" {
  description = "SSH command for the App VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.app_pip.ip_address}"
}

output "db_private_ip" {
  value = azurerm_network_interface.db_nic.private_ip_address
}
