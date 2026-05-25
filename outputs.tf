output "mysql_public_ip" {
  description = "Public IP of the MySQL VM"
  value       = azurerm_public_ip.mysql.ip_address
}

output "app_public_ip" {
  description = "Public IP of the app VM"
  value       = azurerm_public_ip.app.ip_address
}

output "app_url" {
  description = "Flask app URL"
  value       = "https://${azurerm_public_ip.app.ip_address}"
}

output "entra_redirect_uri" {
  description = "Add this URI to your Azure AD app registration under Authentication > Redirect URIs"
  value       = "https://${azurerm_public_ip.app.ip_address}/auth/callback"
}

output "ssh_mysql" {
  description = "SSH command for MySQL VM"
  value       = "ssh ivansto@${azurerm_public_ip.mysql.ip_address}"
}

output "ssh_app" {
  description = "SSH command for app VM"
  value       = "ssh ivansto@${azurerm_public_ip.app.ip_address}"
}
