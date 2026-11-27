variable "region" {
  description = "AWS region of the demo (the bootstrap roles allow only this one)"
  type        = string
  default     = "eu-north-1"
}

variable "name_prefix" {
  description = "Prefix of every demoOTA resource name; the apply role is scoped to it"
  type        = string
  default     = "demo-ota"
}

variable "project_tag" {
  description = "Value of the Project tag on every demoOTA resource"
  type        = string
  default     = "demoOTA"
}

variable "cache_expiration_days" {
  description = <<-EOT
    Days after creation when cache objects (Yocto downloads, sstate)
    expire. S3 lifecycle rules count from creation, not from the last
    read; a rebuild re-uploads what it still needs.
  EOT
  type        = number
  default     = 30
}

variable "artifacts_noncurrent_days" {
  description = "Days an overwritten or deleted artifact version is kept before it expires"
  type        = number
  default     = 7
}
