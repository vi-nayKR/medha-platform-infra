variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Token with Zone DNS, Zone Rulesets, and Zero Trust Access edit permissions."
}

variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tunnel_id" {
  type    = string
  default = "bba72ac3-3cdb-4d95-9bbf-f1884f4b79e9"
}

variable "access_emails" {
  type        = set(string)
  description = "People allowed to open admin and MinIO console hostnames."
  validation {
    condition     = length(var.access_emails) > 0
    error_message = "At least one Access email is required."
  }
}

variable "admin_prod_pages_project" {
  type    = string
  default = "medha-admin-panel"
}
