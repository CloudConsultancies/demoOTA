terraform {
  required_version = ">= 1.10" # S3 native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State lives in the bucket this configuration creates, under
  # bootstrap/. The bucket name is passed at init time
  # (make bootstrap-init). A fresh account has no bucket yet: the first
  # apply runs with local state (backend_override.tf), then migrates.
  # See README.md.
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # Every resource carries Project=demoOTA: cost allocation, the budget
  # filter and the apply role's tag conditions all rely on it.
  default_tags {
    tags = {
      Project   = var.project_tag
      ManagedBy = "terraform"
      Stack     = "demo-ota-bootstrap"
    }
  }
}
