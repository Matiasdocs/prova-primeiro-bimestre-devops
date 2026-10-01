terraform {
  required_version = ">= 1.9.0, < 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
    }
  }
  # bucket é informado pelo output do bootstrap em terraform init.
  backend "s3" {
    key            = "reservas/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "technova-reservas-tf-locks"
  }
}
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "technova-reservas"
      Environment = "learner-lab"
      ManagedBy   = "terraform"
    }
  }
}
