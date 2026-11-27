terraform {
  required_version = ">= 1.10" # S3 native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State in the bootstrap's bucket, under storage/. The bucket name is
  # passed at init time (make infra-init, AWS_TFSTATE_BUCKET in CI).
  backend "s3" {
    key          = "storage/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # Project=demoOTA: cost allocation, the budget filter and the apply
  # role's tag conditions rely on it.
  default_tags {
    tags = {
      Project   = var.project_tag
      ManagedBy = "terraform"
      Stack     = "demo-ota-storage"
    }
  }
}
