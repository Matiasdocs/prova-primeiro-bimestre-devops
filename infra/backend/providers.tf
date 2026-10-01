terraform {
  required_version = ">= 1.9.0, < 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
    }
  }
  # Bootstrap independente: mantém state local, fora do Git.
  backend "local" {}
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
