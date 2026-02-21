output "lb_public_ip" {
  description = "Public IP of the Azure Load Balancer (access the app here)"
  value       = azurerm_public_ip.lb_pip.ip_address
}

output "app_url" {
  description = "Application URL"
  value       = "http://${azurerm_public_ip.lb_pip.ip_address}"
}

output "ssh_app_vm_0" {
  description = "SSH command for App VM 0 (through LB NAT rule)"
  value       = "ssh -p 2201 ${var.admin_username}@${azurerm_public_ip.lb_pip.ip_address}"
}

output "ssh_app_vm_1" {
  description = "SSH command for App VM 1 (through LB NAT rule)"
  value       = "ssh -p 2202 ${var.admin_username}@${azurerm_public_ip.lb_pip.ip_address}"
}

output "db_primary_private_ip" {
  description = "Private IP of the PostgreSQL primary DB VM"
  value       = azurerm_network_interface.db_primary_nic.private_ip_address
}

output "db_replica_private_ip" {
  description = "Private IP of the PostgreSQL replica DB VM"
  value       = azurerm_network_interface.db_replica_nic.private_ip_address
}
