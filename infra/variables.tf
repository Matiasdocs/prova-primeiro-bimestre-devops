variable "access_cidr" {
  description = "IPv4 público do aluno em /32; limita SSH e API."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.access_cidr)) && can(regex("/32$", var.access_cidr))
    error_message = "Informe um CIDR IPv4 /32 válido."
  }
}
variable "ssh_public_key" {
  description = "Conteúdo da chave pública SSH; a chave privada nunca entra no Terraform."
  type        = string
  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.ssh_public_key))
    error_message = "Use uma chave pública SSH ed25519 ou RSA."
  }
}
variable "db_password" {
  description = "Senha exclusiva do laboratório: 16–64 caracteres alfanuméricos, _ ou -."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{16,64}$", var.db_password))
    error_message = "Use 16–64 caracteres alfanuméricos, _ ou -."
  }
}

variable "api_extra_cidrs" {
  description = "IPv4s adicionais /32 autorizados apenas na API, como o do professor."
  type        = set(string)
  default     = []
  validation {
    condition = alltrue([
      for cidr in var.api_extra_cidrs : can(cidrnetmask(cidr)) && can(regex("/32$", cidr))
    ])
    error_message = "Cada origem adicional deve ser um CIDR IPv4 /32 válido."
  }
}
