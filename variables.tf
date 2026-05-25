variable "subscription_id" {
  description = "Azure subscription ID — provide in terraform.tfvars (gitignored)"
  type        = string
}

variable "entra_client_secret" {
  description = "Microsoft Entra app client secret — provide in terraform.tfvars (gitignored)"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "admin_username" {
  description = "VM admin username"
  type        = string
  default     = "ivansto"
}

variable "admin_password" {
  description = "VM admin password"
  type        = string
  default     = "ClaudeCode2023!"
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "entra_client_id" {
  description = "Microsoft Entra app client ID"
  type        = string
  default     = "1cc4b858-20ae-43da-ae84-506eeb8851c5"
}

variable "entra_tenant_id" {
  description = "Microsoft Entra tenant ID"
  type        = string
  default     = "097f33a9-6fc9-423f-923e-f9e3a3122986"
}

variable "flask_secret_key" {
  description = "Flask secret key"
  type        = string
  default     = "f7596fe3803e011564f5ff8de4a96d218ae6a1ed0d83b0d712974ac9e8d17752"
}

variable "db_password" {
  description = "MySQL flask_user password"
  type        = string
  default     = "secretpass1"
}

variable "dns_label" {
  description = "DNS label for the app VM public IP — must be unique within the Azure region. Gives: <label>.westeurope.cloudapp.azure.com"
  type        = string
  default     = "flask-notes-ivansto"
}
