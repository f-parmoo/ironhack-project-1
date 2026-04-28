terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "voting-project-tf-state-bucket-ha"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "voting-project-tf-state-lock-ha"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}



provider "aws" {
  region = var.aws_region
}

