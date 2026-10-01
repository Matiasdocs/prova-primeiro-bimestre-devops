variable "name" { type = string }
variable "vpc_id" { type = string }
variable "access_cidr" { type = string }

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
